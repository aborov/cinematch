module MemoryMonitor
  class << self
    def log_memory_usage(label)
      memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      Rails.logger.info "Memory Usage at #{label}: #{memory_mb}MB"
      
      if memory_mb > 400 # Alert if approaching 512MB limit
        Rails.logger.warn "High memory usage detected: #{memory_mb}MB"
        GC.start # Force garbage collection
      end
    end
  end
end

# Add to your jobs:
class FetchContentJob < ApplicationJob
  before_perform do |job|
    MemoryMonitor.log_memory_usage("Before FetchContentJob")
  end
  
  after_perform do |job|
    MemoryMonitor.log_memory_usage("After FetchContentJob")
  end
end 
