# frozen_string_literal: true

module Crawler
  # Serves a deterministic company website from disk. Same input, same site,
  # every run -- and never a byte of network traffic.
  #
  # It answers for exactly one domain: acme.test.
  #
  # It used to substitute any domain's name into the fixture so the workflow
  # could be exercised against whatever a developer pasted in. That made fake
  # output indistinguishable from real output -- a scan of a real company came
  # back with plausible findings, real-looking URLs on its own subdomains, and
  # nothing to signal that every word was invented. Refusing is the only safe
  # behaviour: fake mode exists to avoid spending money, not to fabricate
  # answers about real companies.
  class Fake < Client
    class UnknownSite < Error; end
    FIXTURE_ROOT = Rails.root.join("test/fixtures/sites")
    FIXTURE_DOMAIN = "acme.test"
    FIXTURE_NAME = "Acme"

    # Fixture subdirectory -> the subdomain that serves it.
    SUBDOMAINS = { "docs" => "docs", "developers" => "developers", "help" => "help", "trust" => "trust" }.freeze

    def initialize(fixture: "acme")
      @root = FIXTURE_ROOT.join(fixture)
      raise Error, "Missing site fixture at #{@root}" unless @root.directory?
    end

    def map(site_url)
      site = Url.site(site_url)
      raise Error, "Unmappable site #{site_url.inspect}" if site.nil?

      ensure_fixture_domain!(site.domain)
      domain = site.domain

      ([ MappedUrl.new(url: "https://#{domain}/", source: "root") ] +
        sitemap_urls(domain) + subdomain_urls(domain) + linked_urls(domain)).uniq(&:url)
    end

    def fetch(url)
      ensure_fixture_domain!(Url.new(url).apex)
      path = fixture_path_for(url)
      raise NotFound, "No fixture page for #{url}" if path.nil? || !path.file?

      raw = localize(path.read, Url.new(url).apex)
      Document.new(
        url: url,
        title: raw[/\A\s*\#\s+(.+)$/, 1]&.strip,
        content: raw.sub(/\A\s*\#\s+.+\n+/, ""),
        http_status: 200,
        links: links_in(raw, url),
        metadata: {
          "fixture" => path.relative_path_from(@root).to_s,
          "content_type" => path.to_s.end_with?(".pdf.txt") ? "application/pdf" : "text/markdown"
        }
      )
    end

    private
      def ensure_fixture_domain!(domain)
        return if domain == FIXTURE_DOMAIN

        raise UnknownSite, <<~MESSAGE.squish
          Refusing to serve fixture content for #{domain}. Fake mode only knows #{FIXTURE_DOMAIN};
          scanning a real company needs APP_MODE=live and ENABLE_LIVE_AI=true.
        MESSAGE
      end

      def sitemap_urls(domain)
        sitemap = @root.join("sitemap.txt")
        return [] unless sitemap.file?

        sitemap.each_line.filter_map do |line|
          line = line.strip
          next if line.blank? || line.start_with?("#")

          MappedUrl.new(url: localize(line, domain), source: "sitemap",
                        metadata: { "sitemap" => "https://#{domain}/sitemap.xml" })
        end
      end

      def subdomain_urls(domain)
        SUBDOMAINS.flat_map do |directory, subdomain|
          dir = @root.join(directory)
          next [] unless dir.directory?

          host = "#{subdomain}.#{domain}"
          # index.md is what the subdomain root serves; listing it again under
          # /index would be the same page at a second URL.
          [ MappedUrl.new(url: "https://#{host}/", source: "subdomain", metadata: { "subdomain" => subdomain }) ] +
            dir.glob("*.md").sort.reject { |file| file.basename(".md").to_s == "index" }.map do |file|
              MappedUrl.new(url: "https://#{host}/#{file.basename('.md')}", source: "subdomain",
                            metadata: { "subdomain" => subdomain })
            end
        end
      end

      # Links found on the main pages, including the PDFs nothing else lists.
      def linked_urls(domain)
        @root.glob("*.md").sort.flat_map do |file|
          origin = "https://#{domain}/#{file.basename('.md')}".sub(%r{/homepage\z}, "/")
          links_in(localize(file.read, domain), origin).map do |url|
            MappedUrl.new(url: url, source: Url.new(url).pdf? ? "pdf_link" : "internal_link",
                          metadata: { "found_on" => origin })
          end
        end
      end

      def links_in(markdown, base)
        markdown.scan(/\[[^\]]*\]\(([^)\s]+)\)/).flatten.filter_map do |href|
          url = Url.new(href, base: base)
          url.to_s if url.valid?
        end.uniq
      end

      # The fixture is only ever served as itself.
      def localize(text, _domain) = text

      def fixture_path_for(raw)
        url = Url.new(raw)
        return nil unless url.valid?

        directory = SUBDOMAINS.key(Url.new(raw, domain: url.apex).subdomain)
        segments = url.path.split("/").reject(&:blank?)

        if directory
          @root.join(directory, "#{segments.first.presence || 'index'}.md")
        elsif segments.empty?
          @root.join("homepage.md")
        elsif url.pdf?
          @root.join("#{segments.join('/')}.txt")
        else
          @root.join("#{segments.join('/')}.md")
        end
      end
  end
end
