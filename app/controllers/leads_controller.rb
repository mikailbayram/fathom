class LeadsController < ApplicationController
  include VisitorSession

  before_action :set_lead, only: %i[show status rescan]

  def index
    render inertia: "Leads/Index", props: {
      leads: Lead.includes(scans: :chatbot).order(:name).map { |lead| LeadPresenter.new(lead).row },
      mode: WebsiteIntelligence.mode.to_s,
      live_ready: LiveReadiness.new.ready?,
      # A queued scan and no worker looks exactly like a slow scan, which is a
      # confusing thing to leave someone staring at.
      worker_running: worker_running?
    }
  end

  def create
    readiness = LiveReadiness.new
    return redirect_to(root_path, inertia: { errors: { website_url: readiness.message } }) unless readiness.ready?

    lead = Lead.for_website(params[:website_url])
    StartScanJob.perform_later(Scan.start!(lead))

    redirect_to lead_path(lead)
  rescue Url::Invalid => error
    redirect_to root_path, inertia: { errors: { website_url: error.message } }
  end

  # The project page: gaps, demo and scan history for one company.
  def show
    presenter = LeadPresenter.new(@lead, origin: request.base_url)
    # The Demo tab subscribes on mount, and a subscription with no visitor
    # cookie is rejected and never retried.
    preview_conversation

    render inertia: "Leads/Show", props: {
      lead: presenter.detail,
      status: presenter.status,
      tab: %w[gaps demo questions scan].include?(params[:tab]) ? params[:tab] : "gaps"
    }
  end

  # Polled while a scan is running. Deliberately small.
  def status
    render json: LeadPresenter.new(@lead).status
  end

  # Reruns from wherever the pipeline actually is, which after a failure is the
  # stage that failed rather than the beginning.
  def rescan
    scan = @lead.latest_scan

    if scan.nil? || scan.completed?
      scan = Scan.start!(@lead)
      StartScanJob.perform_later(scan)
    else
      scan.resume!
    end

    redirect_to lead_path(@lead)
  end

  private
    def preview_conversation
      chatbot = @lead.latest_scan&.chatbot
      conversation_for(chatbot) if chatbot&.publicly_shared?
    end

    def worker_running?
      SolidQueue::Process.where(kind: "Worker").exists?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def set_lead
      @lead = Lead.includes(:scans).find(params[:id])
    end
end
