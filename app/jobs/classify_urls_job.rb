# frozen_string_literal: true

# Stage between mapping and planning: let the cheap model rescue the URLs the
# deterministic rules could not recognise, before the plan throws them away.
class ClassifyUrlsJob < PipelineJob
  def stage = "classifying"

  def perform(scan)
    ensure_mode!(scan)
    refined = AI::Classifier.build(scan).refine!
    Rails.logger.info("ClassifyUrlsJob refined #{refined} URLs on scan #{scan.id}")

    scan.update!(urls_classified_at: Time.current)
    advance(scan)
  end
end
