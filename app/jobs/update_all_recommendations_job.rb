# frozen_string_literal: true

class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :recommendations
  
  # Mark this job to run on the fetcher service
  runs_on_fetcher
  
  # For backward compatibility
  runs_on_jruby
  
  require 'memory_monitor'

  # Custom error class for job cancellation
  class JobCancellationError < StandardError; end

  def perform(options = {})
    log_job_execution(job_id, [options])
    
    # If we're not running on the fetcher service, log a warning and notify admins
    if !Rails.env.development? && !options[:allow_mri_execution]
      error_message = "CRITICAL WARNING: UpdateAllRecommendationsJob is running on the main app instead of the fetcher service. This may cause memory issues and should be investigated immediately."
      Rails.logger.error error_message
      
      # Notify admins
      begin
        AdminMailer.alert_email(
          title: "Fetcher Job Running on Main App",
          message: error_message,
          details: {
            job_class: self.class.name,
            job_id: job_id,
            args: [options],
            ruby_engine: RUBY_ENGINE,
            ruby_version: RUBY_VERSION
          }
        ).deliver_now
      rescue => e
        Rails.logger.error "Failed to send admin alert: #{e.message}"
      end
      
      # Check if we should allow execution on the main app
      allow_mri_execution = options[:allow_mri_execution] || ENV['ALLOW_FETCHER_JOBS_ON_MAIN'] == 'true'
      
      # Abort if we shouldn't run on the main app
      unless allow_mri_execution
        Rails.logger.error "This job should only run on the fetcher service. Aborting execution."
        return { error: "Job aborted - should run on fetcher service" }
      end
    end
    
    # Initialize parameters
    @batch_size = options[:batch_size] || 50
    @memory_threshold_mb = options[:memory_threshold_mb] || 300
    @user_id = options[:user_id]
    @movie_id = options[:movie_id]
    
    # Optimize batch size for memory constraints
    if @memory_threshold_mb < 300
      # For memory-constrained environments, use smaller batches
      @batch_size = [@batch_size, 25].min
      puts "[UpdateAllRecommendationsJob] Memory-constrained environment detected: Reducing initial batch size to #{@batch_size}"
    end
    
    # Log the start of the job
    Rails.logger.info "Starting UpdateAllRecommendationsJob with options: #{options.inspect}"
    Rails.logger.info "Batch size: #{@batch_size}, Memory threshold: #{@memory_threshold_mb}MB"
    
    # Process recommendations
    if @user_id.present?
      update_user_recommendations(@user_id)
    elsif @movie_id.present?
      update_movie_recommendations(@movie_id)
    else
      update_all_recommendations
    end
    
    # Log the completion of the job
    Rails.logger.info "Completed UpdateAllRecommendationsJob"
    
    # Return success
    { status: 'success' }
  end
  
  private
  
  def update_user_recommendations(user_id)
    Rails.logger.info "Updating recommendations for user #{user_id}"
    
    # Implementation details...
    # This would use the recommendation service to update recommendations for a specific user
    
    Rails.logger.info "Completed updating recommendations for user #{user_id}"
  end
  
  def update_movie_recommendations(movie_id)
    Rails.logger.info "Updating recommendations for movie #{movie_id}"
    
    # Implementation details...
    # This would use the recommendation service to update recommendations for a specific movie
    
    Rails.logger.info "Completed updating recommendations for movie #{movie_id}"
  end
  
  def update_all_recommendations
    Rails.logger.info "Updating all recommendations"
    
    # Implementation details...
    # This would use the recommendation service to update all recommendations
    
    Rails.logger.info "Completed updating all recommendations"
  end
  
  def current_memory
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
  
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
