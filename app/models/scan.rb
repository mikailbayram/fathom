# One end-to-end run of the pipeline against a lead's public website.
#
# The database is the source of truth for workflow state: each job records what
# it accomplished and asks Scans::Pipeline what comes next, so a scan can be
# retried, resumed, or rerun without a fragile chain of timers.
class Scan < ApplicationRecord
  STATUSES = %w[
    pending
    mapping
    classifying
    planning
    crawling
    processing
    embedding
    analyzing
    extracting_claims
    checking_visibility
    scoring
    auditing_coverage
    creating_chatbot
    completed
    failed
  ].freeze

  # Ordered as the pipeline runs them, which is what the progress UI walks.
  STAGES = (STATUSES - %w[pending completed failed]).freeze

  belongs_to :lead

  # Declared innermost-first, because Active Record deletes dependents in
  # declaration order: evidence cites chunks, chunks belong to pages, and pages
  # belong to discovered URLs.
  has_many :claims, dependent: :destroy
  has_many :findings, dependent: :destroy
  has_many :chunks, dependent: :delete_all
  has_many :pages, dependent: :delete_all
  has_many :discovered_urls, dependent: :delete_all
  has_many :ai_usages, dependent: :nullify
  has_one :company_profile, dependent: :destroy
  has_one :chatbot, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true

  scope :recent, -> { order(created_at: :desc) }

  delegate :domain, :website_url, to: :lead

  def self.start!(lead)
    create!(lead: lead, status: :pending, mode: WebsiteIntelligence.mode.to_s)
  end

  def running? = !completed? && !failed?

  def work = Work.new(self)

  def stalled? = running? && !pending? && work.pending? == false

  def finished? = completed? || failed?

  # Claims a stage for exactly one caller, and reports whether this call is the
  # one that got it.
  #
  # Several jobs finish at the same instant and each asks the pipeline what is
  # next -- a hundred and twenty claim checks running across eight threads all
  # see the last one resolved and all try to start the coverage audit. Reading
  # the status and then writing it leaves a window between the two, so the test
  # and the write happen in one statement instead.
  #
  # Time never releases a stage. Explicit recovery resets it only after Solid
  # Queue has no unfinished work for this scan.
  def claim_stage(stage)
    claimed = self.class
      .where(id: id)
      .where.not(status: stage.to_s)
      .update_all(status: stage.to_s, started_at: started_at || Time.current, updated_at: Time.current)

    reload if claimed == 1
    claimed == 1
  end

  def resume!
    with_lock do
      return false if pending? || completed? || work.pending?
      return false if running? && !stalled?

      update!(status: :pending, failed_at: nil, failed_stage: nil, error_message: nil)
      StartScanJob.perform_later(self)
      true
    end
  end

  def complete!
    update!(status: :completed, completed_at: Time.current, error_message: nil, failed_stage: nil, failed_at: nil)
    Admission.release!
  end

  # Failures name the stage they happened in so the UI never has to fall back
  # to "something went wrong".
  def fail!(stage:, error:)
    update!(
      status: :failed,
      failed_at: Time.current,
      failed_stage: stage.to_s,
      error_message: error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
    )
    Admission.release!
  end

  def stage_index = STAGES.index(status) || (completed? ? STAGES.length : -1)

  # Built fresh each call, never memoized: a Pipeline snapshots the scan's state
  # on first use, so holding on to one would answer with facts gathered before
  # the work that just finished.
  def pipeline = Pipeline.new(self)

  def viable_findings
    findings.viable.order(friction_score: :desc)
  end

  def estimated_cost_usd
    ai_usages.sum(:estimated_cost) || 0
  end
end
