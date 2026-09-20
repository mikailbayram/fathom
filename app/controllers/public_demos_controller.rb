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

  # The whole controller is outside CSRF, not only the widget script.
  #
  # The authenticity token is derived from the session, and an embedded widget
  # is a third-party iframe: the browser withholds the session cookie, so the
  # token in the page can never validate and every question a widget asked came
  # back 422 before it reached a single line of this controller.
  #
  # Nothing here was protected by it in the first place. CSRF defends ambient
  # authority -- the cookie a browser attaches on a user's behalf -- and these
  # actions have none. The visitor identifies itself with a token it passes
  # explicitly, and every one of these endpoints is reachable by a plain HTTP
  # call from anywhere, so a forged cross-site POST can do nothing a curl
  # command could not. The one that costs money is rate limited instead.
  skip_forgery_protection

  # The demo is meant to be framed on a prospect's own site, so it opts out of
  # Rails' default same-origin framing policy. It is a public page with no
  # authenticated actions, so there is nothing for a framing site to hijack --
  # but the exemption is scoped to this controller and never granted to the
  # internal application.
  before_action :allow_embedding
  before_action :set_chatbot
  # The page load may hand out an identity to someone who arrived without one.
  # A write may not: a POST that cannot say who it is is a client that forgot to
  # identify itself, and answering it in a conversation of its own is how that
  # stays invisible -- which is exactly what the widget did with every question
  # it was ever asked.
  before_action :set_conversation, only: :show
  before_action :require_conversation, only: %i[create handoff]

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

    def require_conversation
      @conversation = identified_conversation_for(@chatbot)
      return if @conversation

      render json: { error: "unidentified" }, status: :bad_request
    end

    def demo_props
      {
        company: @chatbot.name,
        domain: @chatbot.domain,
        slug: @chatbot.slug,
        # The token travels on every request the demo makes, not only on the one
        # that loaded it. An embedded widget is a third-party iframe: the
        # browser sends no cookie with its POSTs, so without this the server
        # mints a new visitor per message, answers a conversation nobody is
        # subscribed to, and the reply never arrives. It is carried in both
        # cases rather than only when embedded, because two paths behaving
        # differently is what hid this.
        ask_path: public_demo_messages_path(@chatbot.slug, v: @conversation.session_id),
        handoff_path: public_demo_handoffs_path(@chatbot.slug, v: @conversation.session_id),
        suggested_questions: @chatbot.suggested_questions(limit: 4),
        messages: @conversation.messages.map(&:as_demo_payload),
        visitor: @conversation.session_id,
        embedded: params[:embed].present?
      }
    end
end
