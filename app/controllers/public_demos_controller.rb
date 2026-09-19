# The shareable prospect-facing chatbot.
#
# This is the one surface a person outside the company can reach, so it assumes
# nothing: no account, no internal identifiers, no scores, no prompts, and a
# rate limit on the endpoint that costs money.
class PublicDemosController < ApplicationController
  include VisitorSession

  # The one surface outside the password. A demo link is meant to be sent to a
  # prospect, who has no credentials and is never going to be given any. It
  # still carries noindex, so a forwarded link does not become a public page.
  skip_before_action :authenticate_operator

  # The widget script is public and stateless; it needs no visitor and belongs
  # to no conversation.
  skip_forgery_protection only: :widget

  # The demo is meant to be framed on a prospect's own site, so it opts out of
  # Rails' default same-origin framing policy. It is a public page with no
  # authenticated actions, so there is nothing for a framing site to hijack --
  # but the exemption is scoped to this controller and never granted to the
  # internal application.
  before_action :allow_embedding
  before_action :set_chatbot
  before_action :set_conversation, except: :widget

  rate_limit to: WebsiteIntelligence.config.public_demo_rate_limit,
             within: WebsiteIntelligence.config.public_demo_rate_period,
             by: -> { "#{params[:slug]}:#{request.remote_ip}" },
             with: -> { render json: { error: "rate_limited" }, status: :too_many_requests },
             only: %i[create handoff]

  def show
    render inertia: "Demos/Show", props: demo_props
  end

  # The widget itself. Rendered as plain text with a JavaScript content type
  # rather than `render js:`, because Rails blocks JS-format responses to
  # non-XHR GETs as a JSONP-hijacking defence -- and this script is loaded by a
  # tag on someone else's page, which is exactly that shape.
  def widget
    response.headers["Access-Control-Allow-Origin"] = "*"
    render plain: WidgetScript.new(@chatbot, origin: request.base_url).to_js,
           content_type: "application/javascript"
  end

  # Answers arrive over Action Cable, not in this response: the question is
  # persisted and handed to a job, so the visitor sees their own message
  # immediately and the reply lands when it is ready.
  def create
    question = params[:question].to_s.strip
    return render(json: { error: "blank" }, status: :unprocessable_entity) if question.blank?

    message = @conversation.messages.create!(role: "user", content: question.truncate(1_000))
    AnswerDemoQuestionJob.perform_later(@conversation, message.content)

    render json: { message: message.as_demo_payload }, status: :created
  end

  # The visitor asks for a person. Nothing is sent anywhere yet -- the question
  # lands on the salesperson's own lead page, which is where they already are.
  def handoff
    question = params[:question].to_s.strip
    return render(json: { error: "blank" }, status: :unprocessable_entity) if question.blank?

    handoff = @conversation.handoffs.create!(
      chatbot: @chatbot,
      question: question.truncate(1_000),
      visitor_email: params[:email].to_s.strip.presence
    )

    message = @conversation.messages.create!(
      role: "assistant",
      content: "I've passed that to #{@chatbot.name}'s team#{" and they'll reply to #{handoff.visitor_email}" if handoff.visitor_email.present?}. " \
               "You'll see their answer here.",
      metadata: { "grounded" => false, "sources" => [], "kind" => "handed_off" }
    )

    render json: { message: message.as_demo_payload }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private
    def allow_embedding
      response.headers.delete("X-Frame-Options")
      response.headers["Content-Security-Policy"] = "frame-ancestors *"
    end

    def set_chatbot
      @chatbot = Chatbot.publicly_shared.includes(scan: :lead).find_by!(slug: params[:slug])
    end

    def set_conversation
      @conversation = conversation_for(@chatbot)
    end

    def demo_props
      {
        company: @chatbot.name,
        domain: @chatbot.domain,
        slug: @chatbot.slug,
        ask_path: public_demo_messages_path(@chatbot.slug),
        handoff_path: public_demo_handoffs_path(@chatbot.slug),
        suggested_questions: @chatbot.suggested_questions(limit: 4),
        messages: @conversation.messages.map(&:as_demo_payload),
        visitor: @conversation.session_id,
        embedded: params[:embed].present?
      }
    end
end
