# frozen_string_literal: true

# Test job for debugging JRuby job routing
class TestJrubyJob < JrubyCompatibleJob
  include JrubyJobConcern
  
  queue_as :default
  
  def perform(options = {})
    # Log the start of the job with memory usage
    Rails.logger.info("TestJrubyJob starting on #{RUBY_ENGINE} #{RUBY_VERSION}")
    Rails.logger.info("Memory usage at start: #{get_memory_usage} MB")
    
    # Log the GoodJob configuration
    Rails.logger.info("GoodJob configuration:")
    Rails.logger.info("  Execution mode: #{GoodJob.configuration.execution_mode}")
    Rails.logger.info("  Queues: #{GoodJob.configuration.queues}")
    Rails.logger.info("  Max threads: #{GoodJob.configuration.max_threads}")
    
    # Log the options
    Rails.logger.info("Options: #{options.inspect}")
    
    # Simulate work
    duration = options[:duration] || 5
    Rails.logger.info("Simulating work for #{duration} seconds...")
    
    # Allocate some memory if requested
    if options[:allocate_memory]
      amount = options[:allocate_memory].to_i
      Rails.logger.info("Allocating #{amount} MB of memory...")
      
      # Allocate memory
      if RUBY_ENGINE == 'jruby'
        # For JRuby, use Java arrays
        begin
          size = amount * 1024 * 1024 / 8  # Convert MB to number of doubles
          memory = java.lang.reflect.Array.newInstance(java.lang.Double.java_class, size)
          Rails.logger.info("Allocated #{amount} MB using Java array")
        rescue => e
          Rails.logger.error("Error allocating memory: #{e.message}")
        end
      else
        # For MRI Ruby, use a large string
        begin
          memory = ' ' * (amount * 1024 * 1024)
          Rails.logger.info("Allocated #{amount} MB using Ruby string")
        rescue => e
          Rails.logger.error("Error allocating memory: #{e.message}")
        end
      end
      
      # Log memory usage after allocation
      Rails.logger.info("Memory usage after allocation: #{get_memory_usage} MB")
    end
    
    # Sleep to simulate work
    sleep(duration)
    
    # Log memory usage at the end
    Rails.logger.info("Memory usage at end: #{get_memory_usage} MB")
    Rails.logger.info("TestJrubyJob completed successfully")
  end
end 
