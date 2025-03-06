namespace :memory do
  desc "Monitor memory usage and perform cleanup when needed"
  task monitor: :environment do
    # Get current memory usage
    memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024 # Convert to MB
    
    Rails.logger.info "[MemoryMonitor] Current memory usage: #{memory_usage} MB"
    
    # If memory usage is above threshold, perform cleanup
    if memory_usage > 400 # 400 MB threshold
      Rails.logger.warn "[MemoryMonitor] Memory usage above threshold (#{memory_usage} MB), performing cleanup"
      
      # Clear Rails caches
      Rails.cache.cleanup if Rails.cache.respond_to?(:cleanup)
      
      # Clear ActiveRecord query cache
      ActiveRecord::Base.connection.clear_query_cache
      
      # Run garbage collection
      before_gc = memory_usage
      GC.start
      GC.compact if GC.respond_to?(:compact)
      
      # Get new memory usage
      memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      Rails.logger.info "[MemoryMonitor] After cleanup: #{memory_usage} MB (freed #{before_gc - memory_usage} MB)"
    end
  end
end

# Add a hook to run memory monitoring in the GoodJob configuration
# This will be loaded in config/initializers/good_job.rb instead of here
# to avoid initialization errors during asset precompilation 
