# One turn of a chatbot conversation. Assistant messages carry their sources in
# metadata so the UI can always show where an answer came from.
class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :conversation

  enum :role, ROLES.index_by(&:itself), validate: true

  validates :content, presence: true

  def sources = Array(metadata["sources"])

  # The one shape the demo speaks, used by both the initial page props and the
  # realtime broadcast, so a message never renders differently depending on how
  # it arrived.
  def as_demo_payload
    {
      id: id,
      role: role,
      content: content,
      grounded: grounded?,
      kind: metadata["kind"] || "answer",
      sources: sources,
      created_at: created_at
    }
  end
  def grounded? = metadata["grounded"] != false
end
