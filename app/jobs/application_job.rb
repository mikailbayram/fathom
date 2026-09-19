class ApplicationJob < ActiveJob::Base
  # Most jobs can safely be retried on deadlock.
  retry_on ActiveRecord::Deadlocked

  # Most jobs are useless if the underlying records are no longer around.
  discard_on ActiveJob::DeserializationError
end
