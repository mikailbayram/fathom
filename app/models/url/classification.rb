# frozen_string_literal: true

class Url
  # What kind of page a URL is, decided from its host and path alone.
  #
  # This runs before any AI, and for the overwhelming majority of URLs it is the
  # only classification that ever happens: spending an LLM call to learn that
  # /blog/2019/hello is a blog post is pure waste. `confident?` is false only
  # when the rules genuinely do not recognise the shape, which is the narrow
  # case AI classification exists for.
  class Classification
    # Subdomains that conventionally hold the deep technical corpus.
    HOST_RULES = {
      /\Adocs?\z/ => "docs",
      /\Adocumentation\z/ => "docs",
      /\Adevelopers?\z/ => "developer_docs",
      /\Aapi\z/ => "developer_docs",
      /\Aengineering\z/ => "developer_docs",
      /\Ahelp\z/ => "help_center",
      /\Asupport\z/ => "support",
      /\A(?:kb|knowledge|knowledgebase|learn|academy)\z/ => "help_center",
      /\Atrust\z/ => "trust",
      /\Asecurity\z/ => "security",
      /\Acompliance\z/ => "trust",
      /\Astatus\z/ => "support"
    }.freeze

    PATH_RULES = [
      [ %r{\A/(?:docs?|documentation|guides?|reference)(?:/|\z)}, "docs" ],
      [ %r{\A/(?:developers?|dev)(?:/|\z)}, "developer_docs" ],
      [ %r{\A/api(?:/|\z)}, "developer_docs" ],
      [ %r{\A/security(?:/|\z)}, "security" ],
      [ %r{\A/(?:trust|compliance)(?:/|\z)}, "trust" ],
      [ %r{\A/(?:pricing|plans)(?:/|\z)}, "pricing" ],
      [ %r{\A/enterprise(?:/|\z)}, "solution" ],
      [ %r{\A/(?:integrations?|connectors?|apps)(?:/|\z)}, "integration" ],
      [ %r{\A/(?:help|faq)(?:/|\z)}, "help_center" ],
      [ %r{\A/support(?:/|\z)}, "support" ],
      [ %r{\A/products?(?:/|\z)}, "product" ],
      [ %r{\A/(?:solutions?|use-cases?|industries)(?:/|\z)}, "solution" ],
      [ %r{\A/features?(?:/|\z)}, "product" ],
      [ %r{\A/(?:legal|terms|privacy|dpa|sla|policies)(?:/|\z)}, "legal" ],
      [ %r{\A/(?:blog|insights)(?:/|\z)}, "blog" ],
      [ %r{\A/(?:news|newsroom|press|announcements)(?:/|\z)}, "news" ],
      [ %r{\A/(?:events?|webinars?)(?:/|\z)}, "news" ],
      [ %r{\A/(?:careers?|jobs)(?:/|\z)}, "careers" ],
      [ %r{\A/(?:authors?|tags?|categor(?:y|ies)|archive)(?:/|\z)}, "blog" ],
      [ %r{\A/(?:about|company|customers|partners|contact|demo|login|signup)(?:/|\z)}, "marketing" ],
      [ %r{\A/(?:resources|library|whitepapers?|case-stud(?:y|ies))(?:/|\z)}, "marketing" ]
    ].freeze

    PRIORITIES = {
      "developer_docs" => 95,
      "security" => 92,
      "trust" => 92,
      "docs" => 90,
      "pricing" => 90,
      "pdf" => 88,
      "integration" => 88,
      "homepage" => 85,
      "help_center" => 82,
      "support" => 80,
      "product" => 60,
      "solution" => 60,
      "legal" => 55,
      "marketing" => 40,
      "other" => 20,
      "blog" => 15,
      "news" => 12,
      "careers" => 5
    }.freeze

    attr_reader :page_type, :priority, :reason

    def self.for(url)
      return new("other", 0, "unparseable url") unless url.valid?
      return new("pdf", PRIORITIES.fetch("pdf"), "PDF document") if url.pdf?
      return new("other", 0, "outside the lead's domain") if url.domain.present? && !url.within_site?
      return new("homepage", PRIORITIES.fetch("homepage"), "site root") if url.root? && url.subdomain.blank?

      from_host(url) || from_path(url) || ambiguous
    end

    def self.from_host(url)
      leaf = url.subdomain.to_s.split(".").first.to_s.downcase
      return nil if leaf.blank?

      _, page_type = HOST_RULES.find { |pattern, _| leaf.match?(pattern) }
      return nil if page_type.nil?

      # A path rule may refine the host's verdict, as on docs.acme.com/api.
      refined = PATH_RULES.find { |pattern, _| match_path?(url, pattern) }&.last
      type = refined || page_type
      # A docs subdomain's own root is documentation, and usually its most
      # important page.
      new(type, PRIORITIES.fetch(type, 20) + (url.root? ? 4 : 0), "#{leaf} subdomain")
    end
    private_class_method :from_host

    def self.from_path(url)
      pattern, page_type = PATH_RULES.find { |candidate, _| match_path?(url, candidate) }
      return nil if page_type.nil?

      new(page_type, PRIORITIES.fetch(page_type, 20), "path matches #{pattern.source}")
    end
    private_class_method :from_path

    # An unrecognised path on the company's own domain is far more likely to be
    # a real content page than junk -- the rules below are English, and plenty of
    # sites are not. Assuming "marketing" keeps such pages in the corpus at low
    # priority instead of discarding them, and confident? stays false so the
    # classifier can still refine it.
    def self.ambiguous = new("marketing", 30, "no deterministic rule matched; assumed marketing", confident: false)
    private_class_method :ambiguous

    # Paths are matched case-insensitively: /Pricing and /pricing are the same
    # kind of page even though they are not the same URL.
    def self.match_path?(url, pattern) = url.path.to_s.downcase.match?(pattern)
    private_class_method :match_path?

    def initialize(page_type, priority, reason, confident: true)
      @page_type = page_type
      @priority = priority.clamp(0, 100)
      @reason = reason
      @confident = confident
    end

    def corpus_type = PageTypes.corpus_for(page_type)

    def confident? = @confident

    def to_h = { page_type: page_type, corpus_type: corpus_type, priority: priority, reason: reason }
  end
end
