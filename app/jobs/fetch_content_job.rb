require 'httparty'

class FetchContentJob < ApplicationJob
  queue_as :content_fetching

  # Set a flag to track if this job is a retry after job runner failure
  attr_accessor :is_fallback_execution
  
  # Constants for batch sizes and limits
  BATCH_SIZE = 50
  MAX_ITEMS_PER_RUN = 1000
  MAX_RETRIES = 3
  BACKOFF_TIMES = [5, 15, 30, 60, 120] # seconds

  # Progress tracking attributes
  attr_accessor :job_start_time, :current_operation, :current_category, :total_operations, :completed_operations

  def perform(options = {})
    # Ensure options is a regular hash
    options = options.to_h if options.respond_to?(:to_h)
    @is_fallback_execution = options.delete(:is_fallback_execution) || false
    
    # Initialize progress tracking
    @job_start_time = Time.current
    @current_operation = nil
    @current_category = nil
    @total_operations = 0
    @completed_operations = 0
    
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !@is_fallback_execution
      Rails.logger.info "[FetchContentJob] Running in production on main app, delegating to job runner service"
      
      # First wake up the job runner with retries
      unless JobRunnerService.wake_up_job_runner(max_retries: 3)
        Rails.logger.warn "[FetchContentJob] Failed to wake up job runner after multiple attempts."
        
        # For long-running jobs like content fetching, we should reschedule rather than run locally
        if should_reschedule_instead_of_fallback?(options)
          reschedule_job(options)
          return
        else
          Rails.logger.warn "[FetchContentJob] Running locally instead as fallback."
        end
      else
        job_id = JobRunnerService.run_job('FetchContentJob', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate to job runner after multiple attempts."
          
          # For long-running jobs like content fetching, we should reschedule rather than run locally
          if should_reschedule_instead_of_fallback?(options)
            reschedule_job(options)
            return
          else
            Rails.logger.warn "[FetchContentJob] Running locally instead as fallback."
          end
        end
      end
    else
      if @is_fallback_execution
        Rails.logger.info "[FetchContentJob] Running as fallback execution after job runner failure"
      else
        Rails.logger.info "[FetchContentJob] Running on job runner or in development, executing locally"
      end
    end
    
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "[FetchContentJob] Starting job with operations: #{options.keys.join(', ')}"
    @start_time = Time.current
    @progress = { total: 0, success: 0, error: 0 }
    
    # Calculate total operations for progress tracking
    @total_operations = 0
    @total_operations += 1 if options[:fetch_new] || options.empty?
    @total_operations += 1 if options[:update_existing] || options.empty?
    @total_operations += 1 if options[:fill_missing] || options.empty?
    
    if options[:fetch_new] || options.empty?
      @current_operation = "fetch_new"
      Rails.logger.info "[FetchContentJob] Daily content fetch - Started at #{@start_time.strftime('%H:%M:%S')}"
      fetch_new_content(options)
      @completed_operations += 1
      log_progress_with_eta
    end
    
    if options[:update_existing] || options.empty?
      @current_operation = "update_existing"
      Rails.logger.info "[FetchContentJob] Bi-weekly content update - Started at #{Time.current.strftime('%H:%M:%S')}"
      update_existing_content(options)
      @completed_operations += 1
      log_progress_with_eta
    end
    
    if options[:fill_missing] || options.empty?
      @current_operation = "fill_missing"
      Rails.logger.info "[FetchContentJob] Missing details fill - Started at #{Time.current.strftime('%H:%M:%S')}"
      fill_missing_details(options)
      @completed_operations += 1
      log_progress_with_eta
    end
    
    duration = Time.current - @start_time
    Rails.logger.info "[FetchContentJob] Job completed in #{duration.round(2)}s. Total content items: #{Content.count}"
    Rails.logger.info "[FetchContentJob] Summary: #{@progress[:success]} successful, #{@progress[:error]} errors, #{@progress[:total]} total"
    
    # Schedule the recommendations update job
    if ENV['JOB_RUNNER_ONLY'] == 'true' && ENV['MAIN_APP_URL'].present?
      # If we're on the job runner, we need to notify the main app to update recommendations
      Rails.logger.info "[FetchContentJob] Notifying main app to update recommendations"
      begin
        # Use a dedicated shared secret for job runner authentication
        shared_secret = ENV['JOB_RUNNER_SECRET'] || ENV['SECRET_KEY_BASE'].to_s[0..15]
        
        max_retries = 2
        retry_count = 0
        
        loop do
          begin
            response = HTTParty.post(
              "#{ENV['MAIN_APP_URL']}/api/job_runner/update_recommendations",
              headers: {
                'Content-Type' => 'application/json',
                'Authorization' => "Bearer #{shared_secret}"
              },
              body: {
                job_id: job_id,
                status: 'completed',
                message: "Content fetch completed successfully. #{@progress[:success]} items processed."
              }.to_json,
              timeout: 10
            )
            
            if response.success?
              Rails.logger.info "[FetchContentJob] Successfully notified main app to update recommendations"
              break
            else
              Rails.logger.warn "[FetchContentJob] Failed to notify main app: #{response.code} - #{response.body}"
              retry_count += 1
              break if retry_count >= max_retries
              sleep(5)
            end
          rescue => e
            Rails.logger.error "[FetchContentJob] Error notifying main app: #{e.message}"
            retry_count += 1
            break if retry_count >= max_retries
            sleep(5)
          end
        end
      rescue => e
        Rails.logger.error "[FetchContentJob] Failed to notify main app: #{e.message}"
      end
    end
  end

  # Class methods for direct invocation
  class << self
    def fetch_new_content(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution]
        Rails.logger.info "[FetchContentJob] Delegating fetch_new_content to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for fetch_new_content. Rescheduling..."
          reschedule_specific_job('fetch_new_content', options)
          return
        end
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'fetch_new_content', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated fetch_new_content to job runner. Job ID: #{job_id}"
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate fetch_new_content to job runner. Rescheduling..."
          reschedule_specific_job('fetch_new_content', options)
        end
      else
        Rails.logger.info "[FetchContentJob] Running fetch_new_content locally"
        run_fetch_new_content_locally(options)
      end
    end
    
    def update_existing_content(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution]
        Rails.logger.info "[FetchContentJob] Delegating update_existing_content to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for update_existing_content. Rescheduling..."
          reschedule_specific_job('update_existing_content', options)
          return
        end
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'update_existing_content', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated update_existing_content to job runner. Job ID: #{job_id}"
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate update_existing_content to job runner. Rescheduling..."
          reschedule_specific_job('update_existing_content', options)
        end
      else
        Rails.logger.info "[FetchContentJob] Running update_existing_content locally"
        run_update_existing_content_locally(options)
      end
    end
    
    def fill_missing_details(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution]
        Rails.logger.info "[FetchContentJob] Delegating fill_missing_details to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for fill_missing_details. Rescheduling..."
          reschedule_specific_job('fill_missing_details', options)
          return
        end
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'fill_missing_details', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated fill_missing_details to job runner. Job ID: #{job_id}"
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate fill_missing_details to job runner. Rescheduling..."
          reschedule_specific_job('fill_missing_details', options)
        end
      else
        Rails.logger.info "[FetchContentJob] Running fill_missing_details locally"
        run_fill_missing_details_locally(options)
      end
    end
    
    private
    
    def reschedule_specific_job(method_name, options = {})
      # Add a flag to indicate this is a fallback execution
      options = options.merge(is_fallback_execution: true)
      
      # Reschedule the job with exponential backoff
      retry_count = options[:retry_count].to_i
      
      if retry_count < 5
        delay = BACKOFF_TIMES[retry_count] # 5s, 15s, 30s, 1m, 2m
        options[:retry_count] = retry_count + 1
        
        Rails.logger.info "[FetchContentJob] Rescheduling #{method_name} to run in #{delay} seconds (attempt #{retry_count + 1}/5)"
        FetchContentJob.set(wait: delay.seconds).public_send(method_name, options)
      else
        # After 5 retries, run locally as fallback
        Rails.logger.warn "[FetchContentJob] Maximum retries reached for #{method_name}. Running locally as fallback."
        options[:is_fallback_execution] = true
        FetchContentJob.public_send("run_#{method_name}_locally", options)
      end
    end
    
    def run_fetch_new_content_locally(options = {})
      require 'rake'
      Rails.application.load_tasks
      
      batch_size = options[:batch_size] || BATCH_SIZE
      max_items = options[:max_items] || MAX_ITEMS_PER_RUN
      
      Rails.logger.info "[FetchContentJob] Running fetch_new_content with batch_size: #{batch_size}, max_items: #{max_items}"
      
      # Set environment variables for the Rake task
      ENV['BATCH_SIZE'] = batch_size.to_s
      ENV['MAX_ITEMS'] = max_items.to_s
      
      Rake::Task['tmdb:fetch_content'].invoke
      Rake::Task['tmdb:fetch_content'].reenable
    end
    
    def run_update_existing_content_locally(options = {})
      require 'rake'
      Rails.application.load_tasks
      
      batch_size = options[:batch_size] || BATCH_SIZE
      max_items = options[:max_items] || MAX_ITEMS_PER_RUN
      
      Rails.logger.info "[FetchContentJob] Running update_existing_content with batch_size: #{batch_size}, max_items: #{max_items}"
      
      # Set environment variables for the Rake task
      ENV['BATCH_SIZE'] = batch_size.to_s
      ENV['MAX_ITEMS'] = max_items.to_s
      
      Rake::Task['tmdb:update_content'].invoke
      Rake::Task['tmdb:update_content'].reenable
    end
    
    def run_fill_missing_details_locally(options = {})
      require 'rake'
      Rails.application.load_tasks
      
      batch_size = options[:batch_size] || BATCH_SIZE
      max_items = options[:max_items] || MAX_ITEMS_PER_RUN
      
      Rails.logger.info "[FetchContentJob] Running fill_missing_details with batch_size: #{batch_size}, max_items: #{max_items}"
      
      # Set environment variables for the Rake task
      ENV['BATCH_SIZE'] = batch_size.to_s
      ENV['MAX_ITEMS'] = max_items.to_s
      
      Rake::Task['tmdb:fill_missing_details'].invoke
      Rake::Task['tmdb:fill_missing_details'].reenable
    end
  end

  private
  
  # Log progress with ETA calculation
  def log_progress_with_eta
    return if @total_operations == 0
    
    elapsed_time = Time.current - @job_start_time
    progress_percentage = (@completed_operations.to_f / @total_operations) * 100
    
    # Only calculate ETA if we have made some progress
    if @completed_operations > 0
      estimated_total_time = elapsed_time / (@completed_operations.to_f / @total_operations)
      estimated_time_remaining = estimated_total_time - elapsed_time
      
      eta = Time.current + estimated_time_remaining
      eta_formatted = eta.strftime('%H:%M:%S')
      
      Rails.logger.info "[FetchContentJob] Progress: #{@completed_operations}/#{@total_operations} operations (#{progress_percentage.round(1)}%)"
      Rails.logger.info "[FetchContentJob] Elapsed: #{format_duration(elapsed_time)}, ETA: #{eta_formatted} (#{format_duration(estimated_time_remaining)} remaining)"
    else
      Rails.logger.info "[FetchContentJob] Progress: #{@completed_operations}/#{@total_operations} operations (#{progress_percentage.round(1)}%)"
      Rails.logger.info "[FetchContentJob] Elapsed: #{format_duration(elapsed_time)}"
    end
  end
  
  # Format duration in a human-readable format
  def format_duration(seconds)
    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    seconds = seconds % 60
    
    if hours > 0
      "#{hours}h #{minutes}m #{seconds}s"
    elsif minutes > 0
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def should_reschedule_instead_of_fallback?(options)
    # For full content fetches or updates, we should reschedule rather than run on main app
    # For smaller operations, we can run locally as fallback
    options.empty? || options[:fetch_new] || options[:update_existing]
  end
  
  def reschedule_job(options = {})
    # Add a flag to indicate this is a fallback execution
    options = options.merge(is_fallback_execution: true)
    
    # Reschedule the job with exponential backoff
    retry_count = options[:retry_count].to_i
    
    if retry_count < 5
      delay = BACKOFF_TIMES[retry_count] # 5s, 15s, 30s, 1m, 2m
      options[:retry_count] = retry_count + 1
      
      Rails.logger.info "[FetchContentJob] Rescheduling to run in #{delay} seconds (attempt #{retry_count + 1}/5)"
      FetchContentJob.set(wait: delay.seconds).perform_later(options)
    else
      # After 5 retries, run locally as fallback
      Rails.logger.warn "[FetchContentJob] Maximum retries reached. Running locally as fallback."
      @is_fallback_execution = true
      perform(options.except(:retry_count))
    end
  end

  def fetch_new_content(options = {})
    Rails.logger.info "[FetchContentJob][New Content] Starting fetch"
    batch_size = options[:batch_size] || BATCH_SIZE
    max_items = options[:max_items] || MAX_ITEMS_PER_RUN
    
    Rails.logger.info "[FetchContentJob][New Content] Using batch_size: #{batch_size}, max_items: #{max_items}"
    
    # Set environment variables for the Rake task
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MAX_ITEMS'] = max_items.to_s
    
    # Track progress
    start_count = Content.count
    
    # Set up logging hooks for the rake task
    setup_rake_task_logging_hooks
    
    Rake::Task['tmdb:fetch_content'].invoke
    Rake::Task['tmdb:fetch_content'].reenable
    
    # Update progress
    end_count = Content.count
    items_added = end_count - start_count
    @progress[:total] += items_added
    @progress[:success] += items_added
    
    Rails.logger.info "[FetchContentJob][New Content] Added #{items_added} new content items"
  rescue => e
    @progress[:error] += 1
    Rails.logger.error "[FetchContentJob][New Content] Error: #{e.message}\n#{e.backtrace.join("\n")}"
    # Continue with other tasks instead of failing the entire job
  end

  def update_existing_content(options = {})
    Rails.logger.info "[FetchContentJob][Update] Starting update of existing content"
    batch_size = options[:batch_size] || BATCH_SIZE
    max_items = options[:max_items] || MAX_ITEMS_PER_RUN
    
    Rails.logger.info "[FetchContentJob][Update] Using batch_size: #{batch_size}, max_items: #{max_items}"
    
    # Set environment variables for the Rake task
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MAX_ITEMS'] = max_items.to_s
    
    # Track progress
    start_time = Time.current
    
    # Set up logging hooks for the rake task
    setup_rake_task_logging_hooks
    
    Rake::Task['tmdb:update_content'].invoke
    Rake::Task['tmdb:update_content'].reenable
    
    # Update progress
    duration = Time.current - start_time
    @progress[:total] += max_items
    @progress[:success] += max_items
    
    Rails.logger.info "[FetchContentJob][Update] Updated content in #{duration.round(2)}s"
  rescue => e
    @progress[:error] += 1
    Rails.logger.error "[FetchContentJob][Update] Error: #{e.message}\n#{e.backtrace.join("\n")}"
    # Continue with other tasks instead of failing the entire job
  end

  def fill_missing_details(options = {})
    Rails.logger.info "[FetchContentJob][Fill Missing] Starting missing details fill"
    batch_size = options[:batch_size] || BATCH_SIZE
    max_items = options[:max_items] || MAX_ITEMS_PER_RUN
    
    Rails.logger.info "[FetchContentJob][Fill Missing] Using batch_size: #{batch_size}, max_items: #{max_items}"
    
    # Set environment variables for the Rake task
    ENV['BATCH_SIZE'] = batch_size.to_s
    ENV['MAX_ITEMS'] = max_items.to_s
    
    # Track progress
    start_time = Time.current
    
    # Set up logging hooks for the rake task
    setup_rake_task_logging_hooks
    
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
    
    # Update progress
    duration = Time.current - start_time
    @progress[:total] += max_items
    @progress[:success] += max_items
    
    Rails.logger.info "[FetchContentJob][Fill Missing] Filled missing details in #{duration.round(2)}s"
  rescue => e
    @progress[:error] += 1
    Rails.logger.error "[FetchContentJob][Fill Missing] Error: #{e.message}\n#{e.backtrace.join("\n")}"
    # Continue with other tasks instead of failing the entire job
  end
  
  # Set up hooks to intercept and enhance logging from rake tasks
  def setup_rake_task_logging_hooks
    # Store original puts method
    original_puts = Kernel.method(:puts)
    
    # Override puts to intercept rake task output and enhance logging
    Kernel.define_singleton_method(:puts) do |*args|
      message = args.first.to_s
      
      # Intercept and enhance specific log messages
      if message.include?('Fetching from source')
        source_match = message.match(/Fetching from source \d+ of \d+: (.+)\.\.\./)
        if source_match
          source_name = source_match[1]
          Rails.logger.info "[FetchContentJob][Current Source] #{source_name}"
        end
      elsif message.include?('Processing')
        if message.include?('movies')
          Rails.logger.info "[FetchContentJob][Processing] Movies from current source"
        elsif message.include?('TV shows')
          Rails.logger.info "[FetchContentJob][Processing] TV Shows from current source"
        end
      elsif message.match(/\[Fetch Content\]\[.+\] (Movies|TV Shows): \d+\/\d+ \(\d+\.\d+%\)/)
        # This is a progress message, log it directly
        Rails.logger.info message
      elsif message.include?('genres from TMDb')
        Rails.logger.info "[FetchContentJob][Genres] Fetching genres from TMDb"
      end
      
      # Call the original puts method
      original_puts.call(*args)
    end
    
    # Ensure we restore the original puts method after the task completes
    at_exit do
      if Kernel.singleton_methods.include?(:puts) && Kernel.method(:puts) != original_puts
        Kernel.singleton_class.send(:remove_method, :puts)
        Kernel.define_singleton_method(:puts, original_puts)
      end
    end
  end
end
