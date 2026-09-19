# frozen_string_literal: true

# Whether a live scan is allowed to start.
#
# The doctor reports this; the controller enforces it. A live scan that begins
# without its credentials would fail several stages in and leave a half-crawled
# lead behind, so it is refused before anything is enqueued.
class LiveReadiness
  REQUIRED_CREDENTIALS = {
    "FIRECRAWL_API_KEY" => "mapping/crawling public websites",
    "OPENAI_API_KEY" => "embeddings + AI analysis"
  }.freeze

  def ready? = missing.empty?

  # Fake and local mode need nothing: that is the point of them.
  def missing
    return [] unless WebsiteIntelligence.live?

    REQUIRED_CREDENTIALS.keys.reject { |name| ENV[name].present? }
  end

  def message
    return nil if ready?

    "Live mode needs #{missing.to_sentence}. Configure #{'it'.pluralize(missing.size)} and run bin/rails app:doctor."
  end

  # The operator-facing checklist, in the shape the spec asks for.
  def checklist
    return nil if ready?

    lines = missing.map do |name|
      "[ ] #{name}\n    Purpose: #{REQUIRED_CREDENTIALS.fetch(name)}\n    Configure as: #{name}"
    end

    "Required now:\n\n#{lines.join("\n\n")}"
  end
end
