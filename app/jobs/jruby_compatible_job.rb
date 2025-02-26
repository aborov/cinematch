# frozen_string_literal: true

# Base class for jobs that can run on JRuby
# This class provides common functionality for memory management and job execution
class JrubyCompatibleJob < ApplicationJob
  # Common functionality for all JRuby-compatible jobs
  
  # Custom error class for job cancellation
  class JobCancellationError < StandardError; end
  
  # Ensure memory_monitor is available
  require 'memory_monitor'
  
  # Override perform to add common functionality
  def perform(options = {})
    # Store the job ID for cancellation checks
    @job_id = provider_job_id
    
    # Convert options to a hash with string keys if it's not already
    options = options.is_a?(Hash) ? options.stringify_keys : {}
    
    # Set up memory monitoring
    setup_memory_monitoring(options)
    
    # Log job start
    log_job_start(options)
    
    # Check for cancellation before starting
    if cancelled?
      log("Job #{@job_id} was cancelled before starting")
      return
    end
    
    # Run the actual job implementation
    begin
      execute(options)
    rescue JobCancellationError => e
      log("Job was cancelled: #{e.message}")
      # No need to re-raise, just let the job end
    rescue => e
      log("Error: #{e.message}")
      log(e.backtrace.join("\n"))
      raise e
    ensure
      # Clean up after job execution
      cleanup
    end
  end
  
  protected
  
  # This method should be implemented by subclasses
  def execute(options)
    raise NotImplementedError, "Subclasses must implement execute"
  end
  
  # Set up memory monitoring based on options
  def setup_memory_monitoring(options)
    @memory_monitor = MemoryMonitor.new
    
    # Use options passed to the job first, then environment variables, then defaults
    @memory_threshold_mb = (options['memory_threshold_mb'] || ENV['MEMORY_THRESHOLD_MB'] || '400').to_i
    @max_batch_size = (options['max_batch_size'] || ENV['MAX_BATCH_SIZE'] || '100').to_i
    @batch_size = (options['batch_size'] || ENV['BATCH_SIZE'] || '30').to_i
    @min_batch_size = (options['min_batch_size'] || ENV['MIN_BATCH_SIZE'] || '5').to_i
    @processing_batch_size = (options['processing_batch_size'] || ENV['PROCESSING_BATCH_SIZE'] || '10').to_i
    
    # Set environment variables for rake tasks and other components
    ENV['MEMORY_THRESHOLD_MB'] = @memory_threshold_mb.to_s
    ENV['MAX_BATCH_SIZE'] = @max_batch_size.to_s
    ENV['BATCH_SIZE'] = @batch_size.to_s
    ENV['MIN_BATCH_SIZE'] = @min_batch_size.to_s
    ENV['PROCESSING_BATCH_SIZE'] = @processing_batch_size.to_s
    
    # Set JRuby-specific memory options if running on JRuby
    if RUBY_ENGINE == 'jruby'
      # Tune JRuby GC for better performance with memory-intensive tasks
      java.lang.System.setProperty('jruby.gc.strategy', 'balanced')
      
      # Set initial and maximum heap size if not already set
      unless java.lang.System.getProperty('jruby.memory.max')
        # Set max heap to 400MB for free tier (leaving some room for the JVM itself)
        java.lang.System.setProperty('jruby.memory.max', '400m')
      end
      
      # Enable invokedynamic which can improve performance
      java.lang.System.setProperty('jruby.compile.invokedynamic', 'true')
      
      log("Running on JRuby #{JRUBY_VERSION} with memory optimizations")
    end
  end
  
  # Log job start with memory usage
  def log_job_start(options)
    current_memory = memory_usage_mb
    job_name = self.class.name
    
    log("Starting #{job_name} (ID: #{@job_id}) with options: #{options.inspect}")
    log("Memory threshold: #{@memory_threshold_mb}MB, Initial batch size: #{@batch_size}, Max batch size: #{@max_batch_size}")
    log("Current memory: #{current_memory}MB")
    
    # Initial aggressive memory cleanup
    @memory_monitor.aggressive_memory_cleanup
    log("Initial memory after cleanup: #{@memory_monitor.mb.round(1)}MB")
  end
  
  # Clean up after job execution
  def cleanup
    end_time = Time.now
    duration = (end_time - @start_time).round(1) if @start_time
    final_memory = @memory_monitor.mb.round(1)
    
    log("Finished at #{end_time}#{duration ? ", Duration: #{duration}s" : ""}. Final memory usage: #{final_memory}MB")
    
    # Final memory cleanup
    @memory_monitor.aggressive_memory_cleanup
    
    # Reset database connections
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.respond_to?(:disconnect!)
      log("Disconnecting database connections...")
      ActiveRecord::Base.connection_pool.disconnect!
    end
    
    # Try to compact heap if supported
    if GC.respond_to?(:compact)
      log("Compacting heap...")
      GC.compact
    end
    
    # JRuby-specific cleanup
    if RUBY_ENGINE == 'jruby'
      log("Running JRuby-specific cleanup...")
      # Request a full GC from the JVM
      java.lang.System.gc
    end
  end
  
  # Check if the job has been cancelled
  def cancelled?
    return false unless @job_id
    
    cancelled = JobCancellationService.cancelled?(@job_id)
    log("Job #{@job_id} cancellation check: #{cancelled}") if cancelled
    cancelled
  end
  
  # Check for cancellation and raise an error if cancelled
  def check_cancellation
    if cancelled?
      log("Job #{@job_id} was cancelled during processing")
      raise JobCancellationError, "Job was cancelled by user"
    end
  end
  
  # Get current memory usage in MB
  def memory_usage_mb
    if RUBY_ENGINE == 'jruby'
      # JRuby-specific memory usage
      runtime = java.lang.Runtime.getRuntime
      ((runtime.totalMemory - runtime.freeMemory) / 1024 / 1024).to_i
    else
      # MRI Ruby memory usage
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
    end
  end
  
  # Check if system load is high
  def system_load_high?
    begin
      case RUBY_PLATFORM
      when /darwin/
        # macOS
        load_avg = `sysctl -n vm.loadavg`.split[1].to_f
        processor_count = `sysctl -n hw.ncpu`.to_i
        normalized_load = load_avg / processor_count
      when /linux/
        # Linux
        load_avg = File.read('/proc/loadavg').split[0].to_f
        processor_count = File.read('/proc/cpuinfo').scan(/^processor/).count
        normalized_load = load_avg / processor_count
      else
        # Default to a conservative value if we can't determine
        normalized_load = 0.7
      end
      
      # Consider load high if it's above 70% of available CPU
      is_high = normalized_load > 0.7
      log("System load check: #{normalized_load.round(2)} (#{is_high ? 'HIGH' : 'normal'})")
      is_high
    rescue => e
      log("Error checking system load: #{e.message}")
      # Default to assuming high load if we can't check
      true
    end
  end
  
  # Throttle processing if system load is high
  def throttle_if_needed
    if system_load_high?
      log("System load is high. Throttling for 3 seconds...")
      sleep(3.0)
    end
  end
  
  # Log a message with the job name prefix
  def log(message)
    job_name = self.class.name.gsub('Job', '')
    puts "[#{job_name}] #{message}"
    Rails.logger.info("[#{job_name}] #{message}") if defined?(Rails) && Rails.logger
  end
end 
