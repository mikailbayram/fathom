# frozen_string_literal: true

# How hard a buyer would have to work to reach an answer, as a band rather than
# a number of minutes.
#
#   SearchEffort.label("long_hunt")   # => "30-45 min to find"
#   SearchEffort.derive(page: page, coverage: 0.1, domain: "acme.com")
#
# The vocabulary lives here for the same reason PageTypes does: the prompt that
# asks for the judgement, the rule that stands in for it when no model ran, and
# the badge that displays it all have to mean the same four things.
#
# Bands, not minutes. Where an answer sits on a website is knowable -- the page
# type, the subdomain, the depth. How long a particular person spends looking
# for it is not, and a figure like "6 min" computed from path segments reads as
# a measurement when it is really an opinion with decimal places. A band is the
# same opinion, stated at the precision we actually have.
module SearchEffort
  BANDS = {
    # The pages a buyer meets lead them to it.
    "signposted" => {
      label: "1-2 min to find",
      short: "1-2 min",
      seconds: 120,
      meaning: "The pages a buyer meets lead them to this."
    },
    # Off the journey, but a determined buyer gets there.
    "short_hunt" => {
      label: "10-15 min to find",
      short: "10-15 min",
      seconds: 780,
      meaning: "Not on the buyer's path, but the nav or site search would get them there."
    },
    # Only reachable by deliberately working through the deep content.
    "long_hunt" => {
      label: "30-45 min to find",
      short: "30-45 min",
      seconds: 2_250,
      meaning: "Only reachable by deliberately working through documentation, a trust centre or a PDF."
    },
    # Nothing on the site would lead anyone here.
    "dead_end" => {
      label: "Most would never find it",
      short: "Never",
      seconds: nil,
      meaning: "Nothing on the site leads a buyer here. They email sales, or assume the answer is no."
    }
  }.freeze

  ALL = BANDS.keys.freeze
  DEFAULT = "short_hunt"

  # Deep page types that are a hunt even when they sit on the main domain.
  BURIED = %w[pdf legal trust developer_docs].freeze

  # Above this the buyer-visible pages say enough to point the way, whatever
  # the answer's own page type. Matches FrictionScore::PROMINENT_CONFIDENCE:
  # one threshold for "the marketing site half-says this", not two.
  SIGNPOSTED_COVERAGE = 0.5
  # Below this there is no trace on the buyer's path at all.
  SILENT_COVERAGE = 0.1

  def self.valid?(band) = ALL.include?(band.to_s)

  def self.band(name) = BANDS.fetch(name.to_s, BANDS.fetch(DEFAULT))

  def self.label(name) = band(name)[:label]
  def self.short_label(name) = band(name)[:short]
  def self.seconds(name) = band(name)[:seconds]
  def self.meaning(name) = band(name)[:meaning]

  # The rule that stands in for the judgement: used in fake mode, and for any
  # finding scored before a model was asked. Deliberately coarse -- it knows
  # where the answer lives and how much of it the buyer-visible pages give away,
  # which is enough to pick a band and not enough to pick a minute.
  def self.derive(page:, coverage: 0.0, domain: nil)
    return "dead_end" if page.nil?

    coverage = coverage.to_f.clamp(0.0, 1.0)
    return "signposted" if coverage >= SIGNPOSTED_COVERAGE

    page_type = page.page_type.to_s
    return "signposted" if page_type == "homepage"
    return coverage >= SILENT_COVERAGE ? "signposted" : "short_hunt" if PageTypes::BUYER_VISIBLE.include?(page_type)
    return "dead_end" if coverage < SILENT_COVERAGE && (BURIED.include?(page_type) || off_domain?(page, domain))
    return "long_hunt" if BURIED.include?(page_type) || off_domain?(page, domain)

    "short_hunt"
  end

  # docs.acme.com is a different site as far as anyone browsing the marketing
  # pages is concerned.
  def self.off_domain?(page, domain)
    return false if domain.blank?

    Url.new(page.canonical_url, domain: domain).subdomain.present?
  end
end
