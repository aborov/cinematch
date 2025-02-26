# frozen_string_literal: true

class UpdateAllRecommendationsJob < JrubyCompatibleJob
  queue_as :recommendations
  
  # Mark this job to run on JRuby
  runs_on_jruby
  
  require 'memory_monitor'

  # Custom error class for job cancellation
  class JobCancellationError < StandardError; end

  def perform(options = {})
    # Store the job ID for cancellation checks
    @job_id = provider_job_id
    
    # Convert options to a hash with string keys if it's not already
    options = options.is_a?(Hash) ? options.stringify_keys : {}
    
    @start_time = Time.now
    @memory_monitor = MemoryMonitor.new
    
    # Use options passed to the job first, then environment variables, then defaults
    @memory_threshold_mb = options['memory_threshold_mb'].presence || 
                         ENV['MEMORY_THRESHOLD_MB'].presence || 
                         '400'
    @max_batch_size = options['max_batch_size'].presence || 
                    ENV['MAX_BATCH_SIZE'].presence || 
                    '100'
    @batch_size = options['batch_size'].presence || 
                ENV['BATCH_SIZE'].presence || 
                '30'
    @min_batch_size = options['min_batch_size'].presence || 
                    ENV['MIN_BATCH_SIZE'].presence || 
                    '5'
    
    # Set environment variables for rake tasks and other components
    ENV['MEMORY_THRESHOLD_MB'] = @memory_threshold_mb.to_s
    ENV['MAX_BATCH_SIZE'] = @max_batch_size.to_s
    ENV['BATCH_SIZE'] = @batch_size.to_s
    ENV['MIN_BATCH_SIZE'] = @min_batch_size.to_s
    
    # Convert to integers for use in this job
    @memory_threshold_mb = @memory_threshold_mb.to_i
    @max_batch_size = @max_batch_size.to_i
    @batch_size = @batch_size.to_i
    @min_batch_size = @min_batch_size.to_i
    
    puts "[UpdateAllRecommendationsJob] Starting at #{@start_time}"
    puts "[UpdateAllRecommendationsJob] Memory threshold: #{@memory_threshold_mb}MB, Initial batch size: #{@batch_size}, Max batch size: #{@max_batch_size}"
    
    # Initial aggressive memory cleanup
    @memory_monitor.aggressive_memory_cleanup
    
    # Check system load before starting
    if system_load_high?
      puts "[UpdateAllRecommendationsJob] System load is high. Reducing workload and adding throttling."
      # Reduce batch sizes by 50% if system load is high
      @max_batch_size = (@max_batch_size * 0.5).to_i
      @batch_size = (@batch_size * 0.5).to_i
      
      puts "[UpdateAllRecommendationsJob] Adjusted settings for high load: " + 
           "Max Batch: #{@max_batch_size}, " +
           "Initial Batch: #{@batch_size}"
    end
    
    # Check for cancellation before starting
    if cancelled?
      puts "[UpdateAllRecommendationsJob] Job #{@job_id} was cancelled before starting"
      return
    end
    
    # Track memory trend
    memory_readings = []
    critical_memory_threshold = @memory_threshold_mb * 1.2  # 20% above threshold for critical situations
    warning_memory_threshold = @memory_threshold_mb * 0.9   # Start reducing at 90% of threshold
    
    # Get all users
    users = User.all
    total_users = users.count
    puts "[UpdateAllRecommendationsJob] Found #{total_users} users to update recommendations for"
    
    # Process users in batches
    processed_count = 0
    
    # JRuby optimization: Use smaller batch sizes and more frequent cleanup
    if RUBY_ENGINE == 'jruby'
      # For JRuby, use smaller batches to avoid memory pressure
      @batch_size = [(@batch_size * 0.7).to_i, @min_batch_size].max
      puts "[UpdateAllRecommendationsJob] JRuby detected: Reducing initial batch size to #{@batch_size}"
    end
    
    begin
      # Process users in chunks to allow for better memory management
      chunk_size = 500  # Process users in chunks of 500
      
      # Get user IDs first to avoid loading all users into memory
      user_ids = User.pluck(:id)
      total_chunks = (user_ids.size.to_f / chunk_size).ceil
      
      user_ids.each_slice(chunk_size).with_index do |chunk_ids, chunk_index|
        puts "[UpdateAllRecommendationsJob] Processing user chunk #{chunk_index + 1}/#{total_chunks} (#{chunk_ids.size} users)"
        
        # Aggressive cleanup before each chunk
        @memory_monitor.aggressive_memory_cleanup
        
        # Process this chunk of users
        process_user_chunk(chunk_ids, processed_count, total_users)
        
        # Update processed count
        processed_count += chunk_ids.size
        
        # Log progress after each chunk
        elapsed_time = Time.now - @start_time
        avg_time_per_user = elapsed_time / processed_count
        estimated_remaining = avg_time_per_user * (total_users - processed_count)
        
        puts "[UpdateAllRecommendationsJob] Chunk #{chunk_index + 1} completed. Progress: #{processed_count}/#{total_users} users (#{(processed_count.to_f / total_users * 100).round(1)}%)"
        puts "[UpdateAllRecommendationsJob] Elapsed time: #{elapsed_time.round(1)}s, Estimated remaining: #{estimated_remaining.round(1)}s"
        puts "[UpdateAllRecommendationsJob] Memory usage: #{@memory_monitor.mb.round(1)}MB"
        
        # JRuby-specific: More aggressive cleanup between chunks
        if RUBY_ENGINE == 'jruby'
          puts "[UpdateAllRecommendationsJob] JRuby cleanup between chunks..."
          @memory_monitor.aggressive_memory_cleanup
          java.lang.System.gc
          
          # Reset database connections
          reset_database_connections
          
          # Pause between chunks to allow memory to stabilize
          puts "[UpdateAllRecommendationsJob] Pausing for 10 seconds between chunks..."
          sleep(10.0)
        end
      end
      
      puts "[UpdateAllRecommendationsJob] Completed. Generated recommendations for #{processed_count} users."
    rescue JobCancellationError => e
      puts "[UpdateAllRecommendationsJob] Job was cancelled: #{e.message}"
      # No need to re-raise, just let the job end
    rescue => e
      puts "[UpdateAllRecommendationsJob] Error: #{e.message}"
      puts e.backtrace.join("\n")
      raise e
    ensure
      end_time = Time.now
      duration = (end_time - @start_time).round(1)
      final_memory = @memory_monitor.mb.round(1)
      puts "[UpdateAllRecommendationsJob] Finished at #{end_time}. Duration: #{duration}s. Final memory usage: #{final_memory}MB"
    end
  end
  
  private
  
  # Check if the job has been cancelled
  def cancelled?
    return false unless @job_id
    
    cancelled = JobCancellationService.cancelled?(@job_id)
    puts "[UpdateAllRecommendationsJob] Job #{@job_id} cancellation check: #{cancelled}" if cancelled
    cancelled
  end
  
  # Check for cancellation and raise an error if cancelled
  def check_cancellation
    if cancelled?
      puts "[UpdateAllRecommendationsJob] Job #{@job_id} was cancelled during processing"
      raise JobCancellationError, "Job was cancelled by user"
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
      puts "[UpdateAllRecommendationsJob] System load check: #{normalized_load.round(2)} (#{is_high ? 'HIGH' : 'normal'})"
      is_high
    rescue => e
      puts "[UpdateAllRecommendationsJob] Error checking system load: #{e.message}"
      # Default to assuming high load if we can't check
      true
    end
  end
  
  # Throttle processing if system load is high
  def throttle_if_needed
    if system_load_high?
      puts "[UpdateAllRecommendationsJob] System load is high. Throttling for 3 seconds..."
      sleep(3.0)
    end
  end
  
  # Process a chunk of users
  def process_user_chunk(user_ids, processed_so_far, total_users)
    # Find users in batches to avoid loading all at once
    current_batch_size = @batch_size
    
    # Process in smaller batches
    user_ids.each_slice(current_batch_size) do |batch_ids|
      # Check for cancellation before processing each batch
      check_cancellation
      
      # Check memory and adjust batch size if needed
      current_memory = @memory_monitor.mb
      current_batch_size = adjust_batch_size(current_memory, current_batch_size)
      
      # Load users for this batch
      batch_users = User.where(id: batch_ids)
      
      # Process each user in the batch
      batch_users.each do |user|
        # Check for cancellation before processing each user
        check_cancellation
        
        begin
          # Generate recommendations for the user
          log_frequency = 10  # Log every 10 users
          if (processed_so_far + 1) % log_frequency == 0
            puts "[UpdateAllRecommendationsJob] Generating recommendations for user #{user.id} (#{processed_so_far + 1}/#{total_users})"
          end
          
          # Check memory before processing each user
          current_memory = @memory_monitor.mb
          if current_memory > @memory_threshold_mb * 0.8
            puts "[UpdateAllRecommendationsJob] Memory usage high (#{current_memory.round(1)}MB) before processing user #{user.id}. Running GC..."
            GC.start(full_mark: true, immediate_sweep: true)
          end
          
          # Generate recommendations
          RecommendationService.generate_recommendations_for(user)
          
          # Increment processed count
          processed_so_far += 1
          
          # Log progress periodically
          if processed_so_far % 50 == 0
            elapsed_time = Time.now - @start_time
            avg_time_per_user = elapsed_time / processed_so_far
            estimated_remaining = avg_time_per_user * (total_users - processed_so_far)
            
            puts "[UpdateAllRecommendationsJob] Progress: #{processed_so_far}/#{total_users} users processed (#{(processed_so_far.to_f / total_users * 100).round(1)}%)"
            puts "[UpdateAllRecommendationsJob] Elapsed time: #{elapsed_time.round(1)}s, Estimated remaining: #{estimated_remaining.round(1)}s"
            puts "[UpdateAllRecommendationsJob] Memory usage: #{@memory_monitor.mb.round(1)}MB, Batch size: #{current_batch_size}"
            
            # Throttle if needed
            throttle_if_needed
          end
        rescue => e
          puts "[UpdateAllRecommendationsJob] Error generating recommendations for user #{user.id}: #{e.message}"
          # Continue with next user
        end
      end
      
      # Force GC after each batch
      GC.start(full_mark: true, immediate_sweep: true)
      
      # JRuby-specific: Request a GC after each batch
      if RUBY_ENGINE == 'jruby' && current_memory > @memory_threshold_mb * 0.7
        puts "[UpdateAllRecommendationsJob] JRuby GC after batch..."
        java.lang.System.gc
      end
      
      # Pause between batches to allow memory to stabilize
      sleep(1.0)
    end
  end
  
  # Adjust batch size based on memory usage
  def adjust_batch_size(current_memory, current_batch_size)
    critical_memory_threshold = @memory_threshold_mb * 1.2
    warning_memory_threshold = @memory_threshold_mb * 0.9
    
    if current_memory > critical_memory_threshold
      # Critical memory situation - reduce batch size drastically
      old_batch_size = current_batch_size
      new_batch_size = [(current_batch_size * 0.5).to_i, @min_batch_size].max
      puts "[UpdateAllRecommendationsJob] CRITICAL memory usage (#{current_memory.round(1)}MB). Reducing batch size from #{old_batch_size} to #{new_batch_size}"
      
      # Force aggressive memory cleanup
      @memory_monitor.aggressive_memory_cleanup
      sleep(3.0) # Longer pause for critical situations
      
      return new_batch_size
    elsif current_memory > @memory_threshold_mb
      # Above threshold - reduce batch size
      old_batch_size = current_batch_size
      new_batch_size = [(current_batch_size * 0.7).to_i, @min_batch_size].max
      puts "[UpdateAllRecommendationsJob] HIGH memory usage (#{current_memory.round(1)}MB). Reducing batch size from #{old_batch_size} to #{new_batch_size}"
      
      # Force GC
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0)
      
      return new_batch_size
    elsif current_memory < @memory_threshold_mb * 0.5 && current_batch_size < @max_batch_size
      # Memory usage is low - increase batch size
      old_batch_size = current_batch_size
      new_batch_size = [(current_batch_size * 1.2).to_i, @max_batch_size].min
      puts "[UpdateAllRecommendationsJob] LOW memory usage (#{current_memory.round(1)}MB). Increasing batch size from #{old_batch_size} to #{new_batch_size}"
      
      return new_batch_size
    end
    
    # No change needed
    return current_batch_size
  end
  
  # Reset database connections
  def reset_database_connections
    if defined?(ActiveRecord::Base)
      if ActiveRecord::Base.connection.respond_to?(:clear_query_cache)
        puts "[UpdateAllRecommendationsJob] Clearing database query cache..."
        ActiveRecord::Base.connection.clear_query_cache
      end
      
      if ActiveRecord::Base.connection_pool.respond_to?(:clear_reloadable_connections!)
        puts "[UpdateAllRecommendationsJob] Clearing database connections..."
        ActiveRecord::Base.connection_pool.clear_reloadable_connections!
      end
    end
  end
end
