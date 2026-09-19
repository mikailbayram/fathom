# frozen_string_literal: true

# A single public URL, and everything the pipeline needs to decide about it:
# what it normalizes to, whether it duplicates something we already have, and
# which corpus it belongs in.
#
#   url = Url.new("https://WWW.Acme.com/docs/roles/?utm_source=x#top", domain: "acme.com")
#   url.to_s        # => "https://www.acme.com/docs/roles"   (what we fetch)
#   url.canonical   # => "https://acme.com/docs/roles"       (how we deduplicate)
#   url.page_type   # => "docs"
#
class Url
  class Invalid < StandardError; end

  # Parameters that never change which content is served.
  TRACKING_PARAMS = %w[
    gclid fbclid msclkid dclid yclid igshid mc_cid mc_eid ref referrer
    _ga _gl _hsenc _hsmi hsa_acc hsa_cam vero_id s_kwcid trk
  ].freeze
  TRACKING_PREFIXES = %w[utm_ pk_ piwik_ mtm_ matomo_].freeze

  DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze

  LOCALE_SEGMENT = /\A[a-z]{2}(?:[-_][a-z]{2})?\z/i
  ENGLISH_LOCALES = %w[en en-us en_us].freeze
  PAGINATION_PATH = %r{/(?:page|pagina|seite)/\d+/?\z}i
  DATE_ARCHIVE_PATH = %r{/(?:19|20)\d{2}/(?:0[1-9]|1[0-2])(?:/|\z)}
  PAGINATION_PARAMS = %w[page p offset start].freeze

  attr_reader :raw, :domain

  def initialize(raw, base: nil, domain: nil)
    @raw = raw.to_s.strip
    @base = base
    @domain = domain
    @uri = parse
  end

  def valid? = !@uri.nil?

  # The URL we actually fetch: the host is left as the site published it,
  # because www and apex are not guaranteed to be the same server.
  def to_s
    return "" unless valid?

    @to_s ||= begin
      uri = cleaned_uri
      uri.host = @uri.host.to_s.downcase.delete_suffix(".")
      uri.to_s
    end
  end
  alias normalized to_s

  # The deduplication identity. www is folded into the apex here, because for
  # our purposes acme.com/pricing and www.acme.com/pricing are one page.
  def canonical
    return "" unless valid?

    @canonical ||= cleaned_uri.to_s
  end

  def host = valid? ? @uri.host.downcase.delete_suffix(".") : nil

  def path = valid? ? normalized_path : nil

  def scheme = valid? ? @uri.scheme.downcase : nil

  def pdf? = path.to_s.downcase.end_with?(".pdf")

  def apex = host && self.class.registrable_domain(host)

  def within_site? = domain.present? && apex == self.class.registrable_domain(domain)

  # "docs" for docs.acme.com when the site is acme.com; nil on the apex itself.
  def subdomain
    return nil unless valid? && domain.present?

    site_apex = self.class.registrable_domain(domain)
    # www is the apex as far as classification is concerned, not a subdomain.
    bare_host = host.to_s.delete_prefix("www.")
    return nil unless bare_host.end_with?(site_apex)

    bare_host.delete_suffix(site_apex).delete_suffix(".").presence
  end

  def root? = path == "/"

  # Translations, paginated listings and dated archives duplicate content we
  # either already have or do not want. They are recorded, never crawled.
  def redundant_variant?
    return false unless valid?

    first_segment = path.to_s.split("/").reject(&:blank?).first.to_s
    return true if first_segment.match?(LOCALE_SEGMENT) && !ENGLISH_LOCALES.include?(first_segment.downcase)
    return true if path.to_s.match?(PAGINATION_PATH)
    return true if path.to_s.match?(DATE_ARCHIVE_PATH)

    query_pairs.any? { |key, value| PAGINATION_PARAMS.include?(key.downcase) && value.to_i > 1 }
  end

  def classification = @classification ||= Classification.for(self)

  delegate :page_type, :corpus_type, :priority, :confident?, :reason, to: :classification

  def ==(other) = other.is_a?(Url) && canonical == other.canonical
  alias eql? ==
  def hash = canonical.hash

  def inspect = "#<Url #{canonical.presence || raw.inspect}>"

  class << self
    # Resolves whatever a salesperson typed into the site we are going to map.
    def site(input)
      candidate = input.to_s.strip
      return nil if candidate.blank?

      candidate = "https://#{candidate}" unless candidate.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      url = new(candidate)
      return nil unless url.valid? && url.host.to_s.include?(".")

      Site.new(
        domain: registrable_domain(url.host),
        website_url: "#{url.scheme}://#{url.host}",
        name: display_name(registrable_domain(url.host))
      )
    end

    # The apex domain, so docs.acme.com and www.acme.com map to one company.
    def registrable_domain(host)
      parts = host.to_s.downcase.delete_suffix(".").split(".")
      return parts.join(".") if parts.length <= 2

      # Handles common two-label public suffixes (co.uk, com.au) without
      # shipping the whole public suffix list, which the MVP does not need.
      if parts[-2].length <= 3 && parts[-1].length <= 3
        parts.last(3).join(".")
      else
        parts.last(2).join(".")
      end
    end

    private
      def display_name(apex)
        apex.split(".").first.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
      end
  end

  Site = Data.define(:domain, :website_url, :name)

  private
    def parse
      return nil if raw.blank?
      return nil if raw.start_with?("#", "mailto:", "tel:", "javascript:", "data:")

      uri = @base.present? ? URI.join(@base, raw) : URI.parse(raw)
      return nil unless uri.is_a?(URI::HTTP)
      return nil if uri.host.blank?

      uri
    rescue URI::Error, ArgumentError
      nil
    end

    # Everything both forms share: no fragment, no default port, no tracking,
    # a tidy path and a stable parameter order.
    def cleaned_uri
      uri = @uri.dup
      uri.fragment = nil
      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.to_s.downcase.delete_suffix(".").delete_prefix("www.")
      uri.port = nil if uri.port == DEFAULT_PORTS[uri.scheme.downcase]
      uri.path = normalized_path
      uri.query = normalized_query
      uri
    end

    def normalized_path
      path = @uri.path.to_s
      path = "/" if path.blank?
      path = path.squeeze("/")
      path = path.chomp("/") if path.length > 1
      # An explicit index document is the directory it lives in.
      path.sub(%r{/index\.(?:html?|php)\z}i, "").presence || "/"
    end

    def normalized_query
      pairs = query_pairs.reject { |key, _| tracking?(key) }
      return nil if pairs.empty?

      URI.encode_www_form(pairs.sort_by { |key, value| [ key, value.to_s ] })
    end

    def query_pairs
      return [] if @uri.nil? || @uri.query.blank?

      @query_pairs ||= URI.decode_www_form(@uri.query)
    rescue ArgumentError
      []
    end

    def tracking?(key)
      key = key.to_s.downcase
      TRACKING_PARAMS.include?(key) || TRACKING_PREFIXES.any? { |prefix| key.start_with?(prefix) }
    end
end
