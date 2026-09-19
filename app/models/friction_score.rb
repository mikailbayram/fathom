# frozen_string_literal: true

# How much a finding is worth, computed in plain Ruby from what was persisted.
#
#   score = FrictionScore.new(finding)
#   score.points      # => 94
#   score.breakdown   # => every component, so the UI can explain the number
#
# The models supply inputs -- confidence, importance, which sources answered --
# but never the score itself. A number a model invents cannot be audited, tuned
# or unit tested, and this one is all three.
class FrictionScore
  # Rebalanced for claims. Every claim that reaches scoring is well supported by
  # its source -- extraction already threw out the ones that were not -- so
  # support no longer discriminates and the gap carries most of the weight. It
  # is the thing the product exists to measure.
  WEIGHTS = {
    buyer_importance: 20,
    answer_confidence: 10,
    discoverability_gap: 40,
    source_obscurity: 15,
    specificity: 15
  }.freeze

  # How buried an answer is, by the kind of page holding it. A PDF nobody links
  # to is the extreme; the homepage is the opposite.
  OBSCURITY = {
    "pdf" => 15, "developer_docs" => 14, "docs" => 12, "help_center" => 11,
    "support" => 10, "trust" => 9, "legal" => 7, "integration" => 5,
    "security" => 4, "solution" => 3, "product" => 2, "pricing" => 2,
    "marketing" => 1, "blog" => 1, "news" => 0, "careers" => 0, "homepage" => 0
  }.freeze
  DEFAULT_OBSCURITY = 3

  # A question answered nowhere has no source to rate, so it is scored on how
  # much it matters and how completely it is absent.
  MISSING_WEIGHTS = { buyer_importance: 45, absence: 35 }.freeze

  # Answering a question the buyer-visible site already answers well is not a
  # finding, however interesting the deep corpus is.
  PROMINENTLY_AVAILABLE_PENALTY = 12
  PROMINENT_CONFIDENCE = 0.5

  PLAN_NAMES = /\b(?:Enterprise|Business|Pro|Premium|Starter|Growth|Team)\b/

  def initialize(finding)
    @finding = finding
  end

  def points = components.values.sum.clamp(0, 100)

  def missing? = finding.kind == "missing"

  def breakdown
    components.merge(
      "total" => points,
      "kind" => finding.kind,
      # A missing finding is scored on different components, so the weights of
      # the buried ones would be a misleading thing to publish alongside it.
      "weights" => (missing? ? MISSING_WEIGHTS : WEIGHTS).transform_keys(&:to_s),
      "source_type" => source_type,
      "source_depth" => source_depth
    )
  end

  # A claim always has an answer -- it came from a passage. What decides a
  # finding is whether the claim is well supported by its source.
  def answerable? = finding.answer.present? && finding.full_corpus_confidence >= Claim::MINIMUM_SUPPORT

  # Grounding is already enforced at extraction: a claim that reached here is
  # supported by the passage it cites. What remains is whether it is worth
  # putting in front of a salesperson.
  def viable?
    return points >= WebsiteIntelligence.config.minimum_finding_score if missing?

    answerable? && points >= WebsiteIntelligence.config.minimum_finding_score
  end

  def status
    return viable? ? "viable" : "below_threshold" if missing?
    return "covered" unless answerable?

    viable? ? "viable" : "below_threshold"
  end

  # The kind of page the primary evidence came from.
  def source_type = missing? ? "none" : (primary_source&.page_type.presence || "other")

  # Where in the site that page lives, which is what a salesperson reads first.
  def source_depth
    return "unknown" if primary_source.nil?

    PageTypes::DEEP.include?(source_type) ? "deep" : "buyer_visible"
  end

  # The deep side is not a retrieval result to be weighed against the shallow
  # one -- it is a sentence the company published, quoted. So the gap is simply
  # how much of that a buyer can reach on the marketing journey.
  def gap = (1.0 - finding.buyer_visible_confidence).clamp(0.0, 1.0)

  def to_attributes
    {
      friction_score: points,
      kind: finding.kind,
      discoverability_score: (gap * 100).round(2),
      source_type: source_type,
      source_depth: source_depth,
      status: status,
      score_breakdown: breakdown
    }
  end

  private
    attr_reader :finding

    def primary_source = @primary_source ||= finding.finding_sources.detect(&:is_primary) || finding.finding_sources.first

    def components
      return @components ||= missing_components if missing?

      @components ||= {
        "buyer_importance" => scaled(finding.buyer_importance, :buyer_importance),
        "answer_confidence" => scaled(finding.full_corpus_confidence, :answer_confidence),
        "discoverability_gap" => scaled(gap, :discoverability_gap),
        "source_obscurity" => OBSCURITY.fetch(source_type, DEFAULT_OBSCURITY),
        "specificity" => specificity_points,
        "prominently_available_penalty" => prominence_penalty
      }
    end

    # Nothing was published, so there is no passage to judge and no source to
    # rate as obscure. What remains is how much the question matters and how
    # completely it goes unanswered.
    def missing_components
      {
        "buyer_importance" => (finding.buyer_importance.to_f.clamp(0.0, 1.0) * MISSING_WEIGHTS.fetch(:buyer_importance)).round,
        "absence" => ((1.0 - finding.buyer_visible_confidence.to_f.clamp(0.0, 1.0)) * MISSING_WEIGHTS.fetch(:absence)).round
      }
    end

    def scaled(value, key) = (value.to_f.clamp(0.0, 1.0) * WEIGHTS.fetch(key)).round

    # A question full of exact enterprise terminology, answered with numbers and
    # named plans, is worth more to a salesperson than a vague one.
    def specificity_points
      technical = "#{finding.claim.question_text} #{finding.claim.statement}".downcase.scan(/[a-z0-9][a-z0-9_.-]*/)
                         .count { |term| AI::Lexicon.technical?(term) }
      answer = finding.answer.to_s

      score = [ technical * 3, 9 ].min
      score += 3 if answer.match?(/\d/)
      score += 3 if answer.match?(PLAN_NAMES)
      [ score, WEIGHTS.fetch(:specificity) ].min
    end

    # Measured coverage, not whether a shallow answer happened to clear the
    # answerable bar: a buyer-visible page that half-states the fact has still
    # made it discoverable.
    def prominence_penalty
      return 0 if finding.buyer_visible_confidence < PROMINENT_CONFIDENCE

      -PROMINENTLY_AVAILABLE_PENALTY
    end
end
