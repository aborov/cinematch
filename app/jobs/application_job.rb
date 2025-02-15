# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  before_perform do |job|
    MemoryMonitor.log_memory_usage("Before #{self.class.name}")
  end
  
  after_perform do |job|
    MemoryMonitor.log_memory_usage("After #{self.class.name}")
    GC.start # Force garbage collection after each job
  end
end
