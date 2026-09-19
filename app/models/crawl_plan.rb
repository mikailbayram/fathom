# frozen_string_literal: true

# Stage two: decide which of the discovered URLs are actually worth fetching.
#
#   plan = CrawlPlan.new(scan)
#   plan.select!
#   plan.summary   # => { discovered: 18_247, high: 1_420, selected: 2_100, ... }
#
# Two rules shape the selection. The deep technical corpus is where enterprise
# answers hide, so it gets most of the budget. But a representative buyer-visible
# corpus is always included, because without it there is nothing to compare the
# deep corpus against and the entire product has nothing to say.
class CrawlPlan
  # The share of the budget reserved for buyer-visible pages even when the deep
  # corpus could fill it.
  BUYER_VISIBLE_RESERVE = 0.25

  PRIORITY_BANDS = { high: 80.., medium: 45...80, low: ...45 }.freeze

  def initialize(scan, budget: nil)
    @scan = scan
    @budget = budget || WebsiteIntelligence.config.max_pages_per_scan
  end

  def select!
    ids = selected_ids

    DiscoveredUrl.transaction do
      scan.discovered_urls.update_all(selected_for_crawl: false)
      scan.discovered_urls.where(id: ids).update_all(selected_for_crawl: true)
    end

    scan.update!(pages_selected: ids.size, plan_summary: summary.deep_stringify_keys)
    self
  end

  def summary
    counts = eligible.group(:corpus_type).count

    {
      discovered: scan.discovered_urls.count,
      eligible: eligible.count,
      high_priority: band_count(:high),
      medium_priority: band_count(:medium),
      low_priority: band_count(:low),
      selected: scan.discovered_urls.selected.count,
      buyer_visible_selected: scan.discovered_urls.selected.where(corpus_type: CorpusTypes::BUYER_VISIBLE).count,
      deep_selected: scan.discovered_urls.selected.where(corpus_type: CorpusTypes::DEEP).count,
      buyer_visible_available: counts[CorpusTypes::BUYER_VISIBLE].to_i,
      deep_available: counts[CorpusTypes::DEEP].to_i,
      skipped_offsite_or_low_value: scan.discovered_urls.where(corpus_type: [ CorpusTypes::IGNORED, CorpusTypes::UNKNOWN ]).count,
      skipped_redundant_variants: redundant.count,
      by_host: scan.discovered_urls.selected.group(:host).count.sort_by { |_, count| -count }.to_h,
      budget: budget
    }
  end

  private
    attr_reader :scan, :budget

    # Everything that could reasonably be fetched: in one of the two real
    # corpora, and not a translation, paginated listing or dated archive of
    # something we already have.
    def eligible
      scan.discovered_urls
          .where(corpus_type: CorpusTypes::RETRIEVABLE)
          .where.not(id: redundant.select(:id))
    end

    def redundant
      scan.discovered_urls.where("metadata ->> 'redundant_variant' = 'true'")
    end

    def selected_ids
      buyer_visible = ordered(CorpusTypes::BUYER_VISIBLE)
      deep = ordered(CorpusTypes::DEEP)

      reserve = (budget * BUYER_VISIBLE_RESERVE).floor
      chosen = buyer_visible.first(reserve)
      chosen += deep.first(budget - chosen.size)
      # Any budget the deep corpus did not need goes back to buyer-visible pages.
      chosen += (buyer_visible - chosen).first(budget - chosen.size)

      chosen.first(budget)
    end

    def ordered(corpus)
      @ordered ||= {}
      @ordered[corpus] ||= eligible.where(corpus_type: corpus).by_priority.pluck(:id)
    end

    def band_count(band)
      eligible.where(priority: PRIORITY_BANDS.fetch(band)).count
    end
end
