require "test_helper"

class Corpus::ChunkerTest < ActiveSupport::TestCase
  setup do
    @scan = acme_scan
    @page = build_page(<<~MARKDOWN)
      ## Defining a custom role

      Administrators can define custom RBAC roles with granular resource permissions.

      Custom roles are available on the Enterprise plan.

      ## Limits

      A workspace may define up to 50 custom roles.
    MARKDOWN
  end

  test "splits on headings" do
    pieces = Corpus::Chunker.new(@page).pieces

    assert_equal 2, pieces.size
    assert_equal [ "Defining a custom role", "Limits" ], pieces.map(&:heading)
  end

  test "numbers pieces sequentially from zero" do
    assert_equal [ 0, 1 ], Corpus::Chunker.new(@page).pieces.map(&:position)
  end

  test "carries provenance onto every piece" do
    Corpus::Chunker.new(@page).pieces.each do |piece|
      assert_equal @page.url, piece.metadata["url"]
      assert_equal @page.title, piece.metadata["title"]
      assert_equal "docs", piece.metadata["page_type"]
      assert_equal CorpusTypes::DEEP, piece.metadata["corpus_type"]
      assert piece.metadata["heading"].present?
    end
  end

  test "carries the page title into the text so a section is findable by its page" do
    piece = Corpus::Chunker.new(@page).pieces.first

    assert_includes piece.content, "Custom roles and permissions"
    assert_includes piece.content, "Defining a custom role"
  end

  test "keeps the context out of the prose a reader is shown" do
    piece = Corpus::Chunker.new(@page).pieces.first
    chunk = Chunk.new(content: piece.content, metadata: piece.metadata)

    assert_not chunk.body.start_with?("Custom roles and permissions")
    assert chunk.body.start_with?("Administrators can define")
  end

  test "counts tokens for every piece" do
    Corpus::Chunker.new(@page).pieces.each { |piece| assert_operator piece.token_count, :>, 0 }
  end

  test "respects the target size and overlaps consecutive pieces" do
    paragraphs = Array.new(10) do |index|
      Array.new(6) { |sentence| "Paragraph #{index} sentence #{sentence} about SCIM provisioning." }.join(" ")
    end
    pieces = Corpus::Chunker.new(build_page(paragraphs.join("\n\n")), target_tokens: 120, overlap_tokens: 40).pieces

    assert_operator pieces.size, :>, 1
    pieces.each { |piece| assert_operator piece.token_count, :<=, 240 }

    overlapping = pieces.each_cons(2).count do |first, second|
      tail = first.content.split(/(?<=[.!?])\s+/).last
      second.content.include?(tail.to_s)
    end
    assert_operator overlapping, :>, 0, "consecutive pieces should share a boundary sentence"
  end

  test "splits an oversized paragraph on sentence boundaries" do
    page = build_page("#{'This is a sentence about SCIM provisioning. ' * 80}")
    pieces = Corpus::Chunker.new(page, target_tokens: 100, overlap_tokens: 10).pieces

    assert_operator pieces.size, :>, 1
    pieces.each { |piece| assert piece.content.strip.end_with?(".") }
  end

  test "produces a single piece for a page with no headings" do
    page = build_page("Just one paragraph of prose with no structure at all.")

    assert_equal 1, Corpus::Chunker.new(page).pieces.size
  end

  private
    def build_page(content)
      @page_number = @page_number.to_i + 1
      url = "https://docs.acme.test/roles-#{@page_number}"

      discovered = @scan.discovered_urls.create!(
        url: url, canonical_url: url, host: "docs.acme.test", path: "/roles-#{@page_number}",
        source: "subdomain", page_type: "docs", corpus_type: CorpusTypes::DEEP, priority: 90
      )

      @scan.pages.create!(
        discovered_url: discovered, url: url, canonical_url: url,
        title: "Custom roles and permissions", page_type: "docs", corpus_type: CorpusTypes::DEEP,
        content: content, content_hash: Digest::SHA256.hexdigest(content), word_count: content.split.size
      )
    end
end
