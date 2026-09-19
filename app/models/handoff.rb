# A question the corpus could not answer, handed to a person.
#
# The agent is honest when a company has not published something, but "I can't
# find that" is a dead end for a prospect and a wasted signal for the
# salesperson. A handoff turns it into a request someone can actually answer,
# and the answer goes back into the same conversation the visitor is looking at.
class Handoff < ApplicationRecord
  STATUSES = %w[waiting answered dismissed].freeze

  belongs_to :conversation
  belongs_to :chatbot

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :question, presence: true
  validates :visitor_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :pending, -> { where(status: "waiting").order(created_at: :asc) }

  delegate :scan, to: :chatbot

  # Answering posts into the visitor's thread and pushes it down the wire, so a
  # prospect who left the tab open sees the reply arrive.
  def answer!(text)
    transaction do
      update!(answer: text, status: "answered", answered_at: Time.current)

      message = conversation.messages.create!(
        role: "assistant",
        content: text,
        metadata: { "grounded" => false, "sources" => [], "kind" => "human", "handoff_id" => id }
      )
      ConversationChannel.broadcast_message(message)
      message
    end
  end

  def to_payload
    {
      id: id,
      question: question,
      visitor_email: visitor_email,
      status: status,
      answer: answer,
      asked_at: created_at,
      answered_at: answered_at
    }
  end
end
