# frozen_string_literal: true

# Stage ten: every completed scan gets a grounded chatbot over its own corpus.
class CreateChatbotJob < PipelineJob
  def stage = "creating_chatbot"

  def perform(scan)
    ensure_mode!(scan)

    # A demo with nothing behind it can only disappoint whoever it is sent to.
    if scan.chunks.embedded.none?
      Rails.logger.info("CreateChatbotJob skipped scan #{scan.id}: nothing indexed")
      return advance(scan)
    end
    scan.create_chatbot!(
      name: scan.lead.name,
      slug: Chatbot.generate_slug(scan.domain),
      status: "active",
      public: true,
      system_prompt: system_prompt_for(scan)
    ) if scan.chatbot.nil?

    advance(scan)
  end

  private
    def system_prompt_for(scan)
      profile = scan.company_profile

      <<~TEXT.strip
        You answer questions about #{scan.lead.name} (#{scan.domain}) for a prospective
        enterprise buyer, using only #{scan.lead.name}'s own public website and
        documentation as indexed by this scan.

        Category: #{profile&.product_category}
        Known integrations: #{Array(profile&.integrations).join(', ').presence || 'none recorded'}

        If the indexed sources do not establish an answer, say so plainly rather than
        speculating. Always show the public source an answer came from.
      TEXT
    end
end
