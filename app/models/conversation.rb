# An anonymous visitor's thread with a public demo chatbot. No account needed.
class Conversation < ApplicationRecord
  belongs_to :chatbot
  has_many :messages, -> { order(:created_at, :id) }, dependent: :delete_all, inverse_of: :conversation
  has_many :ai_usages, dependent: :nullify
  has_many :handoffs, dependent: :destroy

  validates :session_id, presence: true

  def self.for_session(chatbot, session_id)
    create_with(chatbot: chatbot).find_or_create_by!(chatbot: chatbot, session_id: session_id)
  end
end
