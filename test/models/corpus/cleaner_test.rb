require "test_helper"

class Corpus::CleanerTest < ActiveSupport::TestCase
  test "strips markup that could be rendered or executed" do
    cleaner = Corpus::Cleaner.new(<<~HTML)
      <script>alert('xss')</script>
      <style>body { display: none }</style>
      <!-- a comment -->
      <p>Custom roles are available on the <strong>Enterprise</strong> plan.</p>
    HTML

    assert_equal "Custom roles are available on the Enterprise plan.", cleaner.text
  end

  test "keeps link text and drops the target" do
    assert_equal "See the roles guide.", Corpus::Cleaner.new("See the [roles guide](https://docs.acme.test/roles).").text
  end

  test "drops images entirely" do
    assert_equal "Before After", Corpus::Cleaner.new("Before ![a diagram](/diagram.png) After").text
  end

  test "collapses whitespace without merging paragraphs" do
    assert_equal "One\n\nTwo", Corpus::Cleaner.new("One\n\n\n\n   Two   ").text
  end

  test "digests identical content identically regardless of whitespace" do
    assert_equal Corpus::Cleaner.new("a  b\n\nc").digest, Corpus::Cleaner.new("a b\nc").digest
    assert_not_equal Corpus::Cleaner.new("a b").digest, Corpus::Cleaner.new("a c").digest
  end

  test "counts words" do
    assert_equal 4, Corpus::Cleaner.new("one two three four").word_count
  end
end
