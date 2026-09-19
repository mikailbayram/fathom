require "test_helper"

class AI::PaceTest < ActiveSupport::TestCase
  setup { AI::Pace.reset! }
  teardown { AI::Pace.reset! }

  test "spaces calls to fit the account's per-minute limit" do
    # Twenty requests a minute is one every three seconds. This is the whole
    # point of pacing: no concurrency setting expresses it, because a single
    # sequential stream of two-and-a-half-second calls already exceeds it.
    with_env("AI_REQUESTS_PER_MINUTE" => "20") do
      assert_in_delta 3.0, AI::Pace.interval_for(AI::Models.analysis), 0.001
    end
  end

  test "does not pace embeddings" do
    # A different model on a different account, and never the constraint.
    # Pacing it would slow every retrieval for nothing.
    with_env("AI_REQUESTS_PER_MINUTE" => "20") do
      assert_equal 0.0, AI::Pace.interval_for(AI::Models.embedding)
    end
  end

  test "pacing can be switched off" do
    with_env("AI_REQUESTS_PER_MINUTE" => "0") do
      assert_equal 0.0, AI::Pace.interval_for(AI::Models.analysis)
    end
  end

  test "concurrent callers queue behind one another instead of leaving together" do
    # Each caller reserves its slot before returning, so six threads take six
    # intervals rather than all measuring from the same last call and departing
    # at once -- which is exactly how a fanned-out stage floods a rate limit.
    with_env("AI_REQUESTS_PER_MINUTE" => "600") do # 0.1s apart
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      6.times.map { Thread.new { AI::Pace.wait_for(AI::Models.analysis) } }.each(&:join)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :>=, 0.5, "six calls at 0.1s apart cannot finish sooner"
    end
  end

  test "an idle period is not banked as credit to burst with" do
    with_env("AI_REQUESTS_PER_MINUTE" => "600") do
      AI::Pace.wait_for(AI::Models.analysis)
      sleep 0.25

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AI::Pace.wait_for(AI::Models.analysis)

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.05,
                      "a call after a gap goes straight through"
    end
  end
end
