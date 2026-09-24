# Streams a public demo conversation to the one visitor it belongs to.
#
# The visitor identifies itself with the signed cookie it was given on its first
# request, and a subscription is only accepted for a conversation whose
# session_id matches. A demo link is shareable; one visitor's thread is not.
class ConversationChannel < ApplicationCable::Channel
  def subscribed
    chatbot = Chatbot.publicly_shared.find_by(slug: params[:slug])
    return reject if chatbot.nil?

    conversation = chatbot.conversations.find_by(session_id: visitor_id)
    return reject if conversation.nil?

    stream_for conversation
  end

  # Broadcast helpers live with the channel so the payload shape is defined once.
  def self.broadcast_message(message)
    broadcast_to(message.conversation, type: "message", message: message.as_demo_payload)
  end

  def self.broadcast_thinking(conversation)
    broadcast_to(conversation, type: "thinking")
  end

  # The reply as it is being written. It carries the whole text each time rather
  # than the latest piece of it, so a client can take the highest sequence it
  # has seen and ignore the rest. See AnswerStream.
  def self.broadcast_answer(conversation, id:, seq:, text:)
    broadcast_to(conversation, type: "answer", id: id, seq: seq, text: text)
  end
end
