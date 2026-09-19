# frozen_string_literal: true

# Answers one visitor question off the request cycle and pushes the reply down
# the wire, so the demo behaves like a chat rather than a form submission.
class AnswerDemoQuestionJob < ApplicationJob
  queue_as :default

  # A visitor should never be left staring at a spinner because a provider had a
  # bad minute; a failed answer becomes an honest message instead.
  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    conversation = job.arguments.first
    Rails.logger.error("AnswerDemoQuestionJob failed for conversation #{conversation&.id}: #{error.class}: #{error.message}")
    next if conversation.nil?

    message = conversation.messages.create!(
      role: "assistant",
      content: "Something went wrong reaching the search index. Please try that question again.",
      metadata: { "grounded" => false, "sources" => [], "error" => true }
    )
    ConversationChannel.broadcast_message(message)
  end

  def perform(conversation, question)
    reply = AI::Responder.build(conversation.chatbot, conversation: conversation).reply(question)

    message = conversation.messages.create!(role: "assistant", content: reply.content, metadata: reply.to_metadata)
    ConversationChannel.broadcast_message(message)
  end
end
