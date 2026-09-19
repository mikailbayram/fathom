require "test_helper"

class EmptyScanTest < ActiveSupport::TestCase
  # A crawl where every page failed used to sail through to "completed", invent
  # a company profile from nothing, assert that the company publishes nothing,
  # and hand a salesperson a demo that could not answer its own suggestions.
  test "a scan that fetched nothing fails and names why" do
    scan = acme_scan
    MapWebsiteJob.perform_now(scan)
    ClassifyUrlsJob.perform_now(scan)
    BuildCrawlPlanJob.perform_now(scan)

    scan.discovered_urls.selected.update_all(crawled_at: Time.current, crawl_error: "Rate limit exceeded")

    CrawlPagesJob.perform_now(scan)

    assert_predicate scan.reload, :failed?
    assert_equal "crawling", scan.failed_stage
    assert_match(/Crawled 0 of/, scan.error_message)
    assert_match(/Rate limit exceeded/, scan.error_message)
  end

  test "no demo is created for a scan with nothing indexed" do
    scan = acme_scan
    CreateChatbotJob.perform_now(scan)

    assert_nil scan.reload.chatbot
  end

  test "suggested questions never include a question the corpus cannot answer" do
    scan = acme_scan
    run_pipeline(scan)

    suggested = scan.chatbot.suggested_questions(limit: 10)
    missing = scan.findings.where(kind: "missing").map { |f| f.claim.question_text }

    assert_predicate suggested, :any?
    assert_empty suggested & missing, "a demo must not open by suggesting what it cannot answer"
  end
end
