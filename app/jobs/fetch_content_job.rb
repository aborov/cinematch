# frozen_string_literal: true

class FetchContentJob < JrubyCompatibleJob
  queue_as :content_fetching
  
  # Mark this job to run on JRuby
  runs_on_jruby
  
  require 'rake'
  require 'memory_monitor'

  def perform(options = {})
    # Store the job ID for cancellation checks
    @job_id = provider_job_id
    
    # Log the job start with memory usage
    current_memory = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    Rails.logger.info "Starting FetchContentJob (ID: #{@job_id}) with options: #{options.inspect}. Current memory: #{current_memory}MB"
    
    # Check for cancellation before starting
    if @job_id && JobCancellationService.cancelled?(@job_id)
      Rails.logger.info "Job #{@job_id} was cancelled before starting"
      return
    end
    
    # Set memory management parameters from options or environment variables
    # These parameters will be used by the MemoryMonitor
    memory_threshold_mb = options[:memory_threshold_mb] || ENV.fetch('MEMORY_THRESHOLD_MB', '300').to_i
    memory_critical_mb = options[:memory_critical_mb] || ENV.fetch('MEMORY_CRITICAL_MB', '400').to_i
    max_batch_size = options[:max_batch_size] || ENV.fetch('MAX_BATCH_SIZE', '50').to_i
    batch_size = options[:batch_size] || ENV.fetch('BATCH_SIZE', '20').to_i
    min_batch_size = options[:min_batch_size] || ENV.fetch('MIN_BATCH_SIZE', '3').to_i
    processing_batch_size = options[:processing_batch_size] || ENV.fetch('PROCESSING_BATCH_SIZE', '5').to_i
    
    # Log the actual parameters being used
    Rails.logger.info "Using memory parameters: threshold=#{memory_threshold_mb}MB, critical=#{memory_critical_mb}MB, " +
                      "max_batch=#{max_batch_size}, batch=#{batch_size}, min_batch=#{min_batch_size}, processing_batch=#{processing_batch_size}"
    
    # Set environment variables for memory management parameters
    # This ensures they are used by the MemoryMonitor and other components
    ENV['MEMORY_THRESHOLD_MB'] = memory_threshold_mb.to_s
    ENV['MEMORY_CRITICAL_MB'] = memory_critical_mb.to_s
    ENV['MAX_BATCH_SIZE'] = max_batch_size.to_s
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MIN_BATCH_SIZE'] = min_batch_size.to_s
    ENV['PROCESSING_BATCH_SIZE'] = processing_batch_size.to_s
    
    # Determine which action to perform based on options
    if options[:action] == 'fetch_new_content'
      fetch_new_content(options)
    elsif options[:action] == 'update_existing_content'
      update_existing_content(options)
    elsif options[:action] == 'fill_missing_details'
      fill_missing_details(options)
    else
      Rails.logger.error "Unknown action: #{options[:action]}"
    end
  rescue => e
    Rails.logger.error "Error in FetchContentJob: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end
  
  private
  
  # Check if the job has been cancelled
  def cancelled?
    return false unless @job_id
    cancelled = JobCancellationService.cancelled?(@job_id)
    Rails.logger.info "Job #{@job_id} cancellation check: #{cancelled}" if cancelled
    cancelled
  end
  
  # Check for cancellation periodically during processing
  def check_cancellation
    if cancelled?
      Rails.logger.info "Job #{@job_id} was cancelled during processing"
      # Instead of throwing a symbol, we'll raise an exception that will be caught by the perform method
      raise JobCancellationError, "Job was cancelled by user"
    end
  end

  # Custom error class for job cancellation
  class JobCancellationError < StandardError; end

  def fetch_new_content(options)
    # Load Rails tasks
    Rails.application.load_tasks
    
    # Default options with string keys
    default_options = {
      'fetch_new' => true,
      'update_existing' => false,
      'fill_missing' => false
    }

    @start_time = Time.now
    @memory_monitor = MemoryMonitor.new
    
    # Get environment variables or use defaults
    memory_threshold_mb = (ENV['MEMORY_THRESHOLD_MB'] || 300).to_i
    max_batch_size = (ENV['MAX_BATCH_SIZE'] || 50).to_i
    batch_size = (ENV['BATCH_SIZE'] || 20).to_i
    processing_batch_size = (ENV['PROCESSING_BATCH_SIZE'] || 5).to_i
    min_batch_size = (ENV['MIN_BATCH_SIZE'] || 3).to_i
    
    Rails.logger.info "Starting fetch_new_content at #{@start_time}"
    Rails.logger.info "Memory threshold: #{memory_threshold_mb}MB, Initial batch size: #{batch_size}, Max batch size: #{max_batch_size}"
    
    # Initial memory cleanup before starting
    @memory_monitor.aggressive_memory_cleanup
    Rails.logger.info "Initial memory usage: #{@memory_monitor.mb.round(1)}MB"
    
    # Check for cancellation before starting
    check_cancellation
    
    Rails.logger.info "Fetching new content..."
    
    # Define the sources to fetch from
    sources = [
      { name: 'Movies by categories', task: 'tmdb:fetch_movies_by_categories' },
      { name: 'TV shows by categories', task: 'tmdb:fetch_tv_shows_by_categories' },
      { name: 'Content by genres', task: 'tmdb:fetch_content_by_genres' },
      { name: 'Content by decades', task: 'tmdb:fetch_content_by_decades' },
      { name: 'Content by keywords', task: 'tmdb:fetch_content_by_keywords' },
      { name: 'Content by language', task: 'tmdb:fetch_content_by_language' }
    ]
    
    Rails.logger.info "Found #{sources.size} sources to fetch from"

    # JRuby optimization: Process sources in smaller chunks with more aggressive cleanup
    chunk_size = RUBY_ENGINE == 'jruby' ? 2 : sources.size
    
    sources.each_slice(chunk_size).with_index do |source_chunk, chunk_index|
      Rails.logger.info "Processing source chunk #{chunk_index + 1}/#{(sources.size.to_f / chunk_size).ceil}"
      
      source_chunk.each_with_index do |source, source_index|
        # Check for cancellation before processing each source
        check_cancellation
        
        source_name = source[:name]
        Rails.logger.info "Fetching from source #{source_index + 1}/#{source_chunk.size} in chunk #{chunk_index + 1}: #{source_name}"
        
        begin
          # Check memory before starting a new source
          current_memory = @memory_monitor.mb
          if current_memory > memory_threshold_mb * 0.6  # Lower threshold for cleanup
            Rails.logger.info "Memory usage before starting #{source_name}: #{current_memory.round(1)}MB. Running aggressive cleanup..."
            @memory_monitor.aggressive_memory_cleanup
            Rails.logger.info "Memory after cleanup: #{@memory_monitor.mb.round(1)}MB"
          end
          
          # Reset database connections before each source
          reset_database_connections
          
          # Set environment variables for the rake task
          ENV['MEMORY_THRESHOLD_MB'] = memory_threshold_mb.to_s
          ENV['MAX_BATCH_SIZE'] = max_batch_size.to_s
          ENV['BATCH_SIZE'] = batch_size.to_s
          ENV['PROCESSING_BATCH_SIZE'] = processing_batch_size.to_s
          ENV['MIN_BATCH_SIZE'] = min_batch_size.to_s
          
          # Pass the job ID to the rake task for cancellation checks
          ENV['CURRENT_JOB_ID'] = @job_id.to_s if @job_id
          
          # Run the rake task
          Rake::Task[source[:task]].reenable
          Rake::Task[source[:task]].invoke
          
          # Check for cancellation after each source
          check_cancellation
          
          # Force aggressive memory cleanup after each source
          Rails.logger.info "Performing aggressive memory cleanup after #{source_name}..."
          @memory_monitor.aggressive_memory_cleanup
          
          # Reset database connections after each source
          reset_database_connections
          
          # Try to compact heap if supported
          if GC.respond_to?(:compact)
            Rails.logger.info "Compacting heap..."
            GC.compact
          end
          
          # JRuby-specific cleanup
          if RUBY_ENGINE == 'jruby'
            Rails.logger.info "Running JRuby-specific cleanup..."
            java.lang.System.gc
          end
          
          # Longer pause between sources to ensure memory is released
          pause_duration = RUBY_ENGINE == 'jruby' ? 20.0 : 15.0
          Rails.logger.info "Pausing for #{pause_duration} seconds to allow memory to stabilize..."
          sleep(pause_duration)
          
          # Force GC again after the pause
          GC.start(full_mark: true, immediate_sweep: true)
          
          Rails.logger.info "Completed source #{source_name}. Memory usage: #{@memory_monitor.mb.round(1)}MB"
        rescue StandardError => e
          Rails.logger.error "[Error][#{source_name}] #{e.message}"
          Rails.logger.error e.backtrace.take(10).join("\n")
          @memory_monitor.aggressive_memory_cleanup
          # Continue with next source instead of failing the entire job
        end
      end
      
      # After each chunk, perform a more thorough cleanup
      if RUBY_ENGINE == 'jruby' && chunk_index < (sources.size.to_f / chunk_size).ceil - 1
        Rails.logger.info "Completed source chunk #{chunk_index + 1}. Performing thorough cleanup..."
        @memory_monitor.aggressive_memory_cleanup
        reset_database_connections
        
        # JRuby-specific: Request a full GC cycle
        java.lang.System.gc
        
        # Longer pause between chunks
        Rails.logger.info "Pausing for 30 seconds between source chunks..."
        sleep(30.0)
      end
    end

    end_time = Time.now
    duration = (end_time - @start_time).round(2)
    Rails.logger.info "Fetch new content completed at #{end_time}"
    Rails.logger.info "Duration: #{duration}s"
    Rails.logger.info "Memory usage: #{@memory_monitor.mb.round(1)}MB"
  end

  def update_existing_content(options)
    # Load Rails tasks
    Rails.application.load_tasks
    
    @start_time = Time.now
    @memory_monitor = MemoryMonitor.new
    
    Rails.logger.info "Starting update_existing_content at #{@start_time}"
    
    # Get environment variables or use defaults
    memory_threshold_mb = (ENV['MEMORY_THRESHOLD_MB'] || 300).to_i
    max_batch_size = (ENV['MAX_BATCH_SIZE'] || 50).to_i
    batch_size = (ENV['BATCH_SIZE'] || 20).to_i
    min_batch_size = (ENV['MIN_BATCH_SIZE'] || 3).to_i
    
    Rails.logger.info "Memory threshold: #{memory_threshold_mb}MB, Initial batch size: #{batch_size}, Max batch size: #{max_batch_size}"
    
    # Initial memory cleanup before starting
    @memory_monitor.aggressive_memory_cleanup
    Rails.logger.info "Initial memory usage: #{@memory_monitor.mb.round(1)}MB"
    
    # Check for cancellation before starting
    check_cancellation
    
    Rails.logger.info "Running update_content task..."
    
    # Check memory before update_content
    current_memory = @memory_monitor.mb
    if current_memory > memory_threshold_mb * 0.6  # Lower threshold for cleanup
      Rails.logger.info "Memory usage before update_content: #{current_memory.round(1)}MB. Running aggressive cleanup..."
      @memory_monitor.aggressive_memory_cleanup
      Rails.logger.info "Memory after cleanup: #{@memory_monitor.mb.round(1)}MB"
    end
    
    # Reset database connections
    reset_database_connections
    
    # Set environment variables for the rake task
    ENV['MEMORY_THRESHOLD_MB'] = memory_threshold_mb.to_s
    ENV['MAX_BATCH_SIZE'] = max_batch_size.to_s
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MIN_BATCH_SIZE'] = min_batch_size.to_s
    
    # Pass the job ID to the rake task for cancellation checks
    ENV['CURRENT_JOB_ID'] = @job_id.to_s if @job_id
    
    # Run the rake task
    Rake::Task['tmdb:update_content'].reenable
    Rake::Task['tmdb:update_content'].invoke
    
    # Check for cancellation after the task
    check_cancellation
    
    # Force aggressive memory cleanup after update_content
    Rails.logger.info "Performing aggressive memory cleanup after update_content..."
    @memory_monitor.aggressive_memory_cleanup
    
    # Reset database connections
    reset_database_connections
    
    # Try to compact heap if supported
    if GC.respond_to?(:compact)
      Rails.logger.info "Compacting heap..."
      GC.compact
    end
    
    # JRuby-specific cleanup
    if RUBY_ENGINE == 'jruby'
      Rails.logger.info "Running JRuby-specific cleanup..."
      java.lang.System.gc
    end
    
    # Pause to allow memory to stabilize
    pause_duration = RUBY_ENGINE == 'jruby' ? 20.0 : 15.0
    Rails.logger.info "Pausing for #{pause_duration} seconds to allow memory to stabilize..."
    sleep(pause_duration)
    
    # Force GC again after the pause
    GC.start(full_mark: true, immediate_sweep: true)
    
    end_time = Time.now
    duration = (end_time - @start_time).round(2)
    Rails.logger.info "Update existing content completed at #{end_time}"
    Rails.logger.info "Duration: #{duration}s"
    Rails.logger.info "Memory usage: #{@memory_monitor.mb.round(1)}MB"
  end

  def fill_missing_details(options)
    # Load Rails tasks
    Rails.application.load_tasks
    
    @start_time = Time.now
    @memory_monitor = MemoryMonitor.new
    
    Rails.logger.info "Starting fill_missing_details at #{@start_time}"
    
    # Get environment variables or use defaults
    memory_threshold_mb = (ENV['MEMORY_THRESHOLD_MB'] || 300).to_i
    max_batch_size = (ENV['MAX_BATCH_SIZE'] || 50).to_i
    batch_size = (ENV['BATCH_SIZE'] || 20).to_i
    min_batch_size = (ENV['MIN_BATCH_SIZE'] || 3).to_i
    
    Rails.logger.info "Memory threshold: #{memory_threshold_mb}MB, Initial batch size: #{batch_size}, Max batch size: #{max_batch_size}"
    
    # Initial memory cleanup before starting
    @memory_monitor.aggressive_memory_cleanup
    Rails.logger.info "Initial memory usage: #{@memory_monitor.mb.round(1)}MB"
    
    # Check for cancellation before starting
    check_cancellation
    
    Rails.logger.info "Running fill_missing_details task..."
    
    # Check memory before fill_missing_details
    current_memory = @memory_monitor.mb
    if current_memory > memory_threshold_mb * 0.6  # Lower threshold for cleanup
      Rails.logger.info "Memory usage before fill_missing_details: #{current_memory.round(1)}MB. Running aggressive cleanup..."
      @memory_monitor.aggressive_memory_cleanup
      Rails.logger.info "Memory after cleanup: #{@memory_monitor.mb.round(1)}MB"
    end
    
    # Reset database connections
    reset_database_connections
    
    # Set environment variables for the rake task
    ENV['MEMORY_THRESHOLD_MB'] = memory_threshold_mb.to_s
    ENV['MAX_BATCH_SIZE'] = max_batch_size.to_s
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MIN_BATCH_SIZE'] = min_batch_size.to_s
    
    # Pass the job ID to the rake task for cancellation checks
    ENV['CURRENT_JOB_ID'] = @job_id.to_s if @job_id
    
    # Run the rake task
    Rake::Task['tmdb:fill_missing_details'].reenable
    Rake::Task['tmdb:fill_missing_details'].invoke
    
    # Check for cancellation after the task
    check_cancellation
    
    # Force aggressive memory cleanup after fill_missing_details
    Rails.logger.info "Performing aggressive memory cleanup after fill_missing_details..."
    @memory_monitor.aggressive_memory_cleanup
    
    # Reset database connections
    reset_database_connections
    
    # Try to compact heap if supported
    if GC.respond_to?(:compact)
      Rails.logger.info "Compacting heap..."
      GC.compact
    end
    
    # JRuby-specific cleanup
    if RUBY_ENGINE == 'jruby'
      Rails.logger.info "Running JRuby-specific cleanup..."
      java.lang.System.gc
    end
    
    # Pause to allow memory to stabilize
    pause_duration = RUBY_ENGINE == 'jruby' ? 20.0 : 15.0
    Rails.logger.info "Pausing for #{pause_duration} seconds to allow memory to stabilize..."
    sleep(pause_duration)
    
    # Force GC again after the pause
    GC.start(full_mark: true, immediate_sweep: true)
    
    end_time = Time.now
    duration = (end_time - @start_time).round(2)
    Rails.logger.info "Fill missing details completed at #{end_time}"
    Rails.logger.info "Duration: #{duration}s"
    Rails.logger.info "Memory usage: #{@memory_monitor.mb.round(1)}MB"
  end
  
  def memory_usage_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
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
      Rails.logger.info "System load check: #{normalized_load.round(2)} (#{is_high ? 'HIGH' : 'normal'})"
      is_high
    rescue => e
      Rails.logger.error "Error checking system load: #{e.message}"
      # Default to assuming high load if we can't check
      true
    end
  end

  # Helper method to reset database connections
  def reset_database_connections
    if defined?(ActiveRecord::Base)
      if ActiveRecord::Base.connection.respond_to?(:clear_query_cache)
        Rails.logger.info "Clearing database query cache..."
        ActiveRecord::Base.connection.clear_query_cache
      end
      
      if ActiveRecord::Base.connection_pool.respond_to?(:clear_reloadable_connections!)
        Rails.logger.info "Clearing database connections..."
        ActiveRecord::Base.connection_pool.clear_reloadable_connections!
      end
    end
  end
end
