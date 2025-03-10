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
  attr_accessor :job_start_time, :current_operation, :current_category, :current_genre, :current_decade, :current_keyword, :current_language, :total_operations, :completed_operations

  def perform(options = {})
    # Handle different input formats
    options = case options
              when Hash
                options.dup # Create a copy to avoid modifying the original
              when Array
                # Convert array format to hash
                options_hash = {}
                options.each_slice(2) do |key, value|
                  key_str = key.to_s
                  options_hash[key_str] = value
                end
                options_hash
              when String
                # Try to parse as JSON if it's a string
                begin
                  JSON.parse(options)
                rescue JSON::ParserError
                  { 'input' => options } # Use as a simple string parameter
                end
              when TrueClass, FalseClass
                { 'fetch_new' => options } # Default to fetch_new for boolean values
              when Integer
                { 'batch_size' => options } # Default to batch_size for integer values
              else
                # For any other type, convert to empty hash
                {}
              end
    
    # Ensure options is a regular hash with indifferent access
    options = options.to_h if options.respond_to?(:to_h)
    options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
    @is_fallback_execution = options.delete(:is_fallback_execution) || options.delete('is_fallback_execution') || false
    
    # Initialize job tracking variables
    @job_start_time = Time.current
    @current_operation = nil
    @current_category = nil
    @current_genre = nil
    @current_decade = nil
    @current_keyword = nil
    @current_language = nil
    
    # Calculate total operations based on options
    @total_operations = 0
    @total_operations += 1 if options[:fetch_new] || options['fetch_new'] || options.empty?
    @total_operations += 1 if options[:update_existing] || options['update_existing'] || options.empty?
    @total_operations += 1 if options[:fill_missing] || options['fill_missing'] || options.empty?
    @completed_operations = 0
    
    # Set up logging hooks to capture rake task output
    setup_rake_task_logging_hooks
    
    Rails.logger.info "[FetchContentJob] Starting content fetch job with options: #{options.inspect}"
    Rails.logger.info "[FetchContentJob] Will perform #{@total_operations} operations"
    
    # Track if any content was added or updated to determine if we need to update recommendations
    content_changes = false
    
    begin
      if options[:fetch_new] || options['fetch_new'] || options.empty?
        @current_operation = "fetch_new"
        @completed_operations += 1
        
        log_progress_with_eta
        Rails.logger.info "[FetchContentJob] Starting fetch_new_content operation (#{@completed_operations}/#{@total_operations})"
        
        new_items_added = fetch_new_content(options)
        # Initialize content_changes if it's nil and add a nil check for new_items_added
        content_changes ||= false
        content_changes = content_changes || (new_items_added.to_i > 0)
        
        Rails.logger.info "[FetchContentJob] Completed fetch_new_content operation. Added #{new_items_added || 0} new items."
      end
      
      if options[:update_existing] || options['update_existing'] || options.empty?
        @current_operation = "update_existing"
        @completed_operations += 1
        
        log_progress_with_eta
        Rails.logger.info "[FetchContentJob] Starting update_existing_content operation (#{@completed_operations}/#{@total_operations})"
        
        significant_updates = update_existing_content(options)
        # Initialize content_changes if it's nil and add a nil check for significant_updates
        content_changes ||= false
        content_changes = content_changes || (significant_updates.to_i > 0)
        
        Rails.logger.info "[FetchContentJob] Completed update_existing_content operation. Updated #{significant_updates || 0} items with significant changes."
      end
      
      if options[:fill_missing] || options['fill_missing'] || options.empty?
        @current_operation = "fill_missing"
        @completed_operations += 1
        
        log_progress_with_eta
        Rails.logger.info "[FetchContentJob] Starting fill_missing_details operation (#{@completed_operations}/#{@total_operations})"
        
        filled_items = fill_missing_details(options)
        # Initialize content_changes if it's nil and add a nil check for filled_items
        content_changes ||= false
        content_changes = content_changes || (filled_items.to_i > 0)
        
        Rails.logger.info "[FetchContentJob] Completed fill_missing_details operation. Filled details for #{filled_items || 0} items."
      end
      
      # Only update recommendations if content has changed
      if content_changes
        Rails.logger.info "[FetchContentJob] Content changes detected. Scheduling recommendation updates."
        
        # Schedule recommendation updates
        if ENV['JOB_RUNNER_ONLY'] == 'true'
          # If we are the job runner, run the job directly
          UpdateAllRecommendationsJob.perform_later(batch_size: 50)
        else
          # Otherwise, delegate to the job runner
          JobRunnerService.run_job('UpdateAllRecommendationsJob', { batch_size: 50 })
        end
      else
        Rails.logger.info "[FetchContentJob] No content changes detected. Skipping recommendation updates."
      end
      
      # Notify the main app that the job is complete
      if ENV['MAIN_APP_URL'].present? && ENV['JOB_RUNNER_ONLY'] == 'true'
        begin
          Rails.logger.info "[FetchContentJob] Notifying main app about job completion"
          
          # Ensure we have the job_id
          job_id = self.job_id || SecureRandom.uuid
          
          response = HTTParty.post(
            "#{ENV['MAIN_APP_URL']}/api/job_runner/update_recommendations",
            body: {
              job_id: job_id,
              status: 'completed',
              message: "Content fetch completed successfully. Content changes: #{content_changes}",
              secret: ENV['JOB_RUNNER_SECRET'] # Add the secret for authentication
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
          
          if response.success?
            Rails.logger.info "[FetchContentJob] Successfully notified main app"
          else
            Rails.logger.error "[FetchContentJob] Failed to notify main app. Status: #{response.code}, Error: #{response.body}"
          end
        rescue => e
          Rails.logger.error "[FetchContentJob] Error notifying main app: #{e.message}"
        end
      end
      
      Rails.logger.info "[FetchContentJob] Content fetch job completed successfully"
    rescue => e
      Rails.logger.error "[FetchContentJob] Error in content fetch job: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    ensure
      # Force garbage collection
      GC.start
      GC.compact if GC.respond_to?(:compact)
    end
  end

  # Class methods for direct invocation
  class << self
    def fetch_new_content(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution] && !options['is_fallback_execution']
        Rails.logger.info "[FetchContentJob] Delegating fetch_new_content to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for fetch_new_content. Rescheduling..."
          reschedule_specific_job('fetch_new_content', options)
          return 0
        end
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'fetch_new_content', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated fetch_new_content to job runner. Job ID: #{job_id}"
          return 0
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate fetch_new_content to job runner. Rescheduling..."
          reschedule_specific_job('fetch_new_content', options)
          return 0
        end
      else
        Rails.logger.info "[FetchContentJob] Running fetch_new_content locally"
        return run_fetch_new_content_locally(options)
      end
    end
    
    def update_existing_content(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution] && !options['is_fallback_execution']
        Rails.logger.info "[FetchContentJob] Delegating update_existing_content to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for update_existing_content. Rescheduling..."
          reschedule_specific_job('update_existing_content', options)
          return 0
        end
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'update_existing_content', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated update_existing_content to job runner. Job ID: #{job_id}"
          return 0
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate update_existing_content to job runner. Rescheduling..."
          reschedule_specific_job('update_existing_content', options)
          return 0
        end
      else
        Rails.logger.info "[FetchContentJob] Running update_existing_content locally"
        return run_update_existing_content_locally(options)
      end
    end
    
    def fill_missing_details(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      # First check if there are any items that need updating
      # This prevents unnecessary job delegation and rescheduling
      needs_update_count = Content.where(tmdb_last_update: nil)
                                 .or(Content.where('tmdb_last_update < ?', 2.weeks.ago))
                                 .count
      
      if needs_update_count == 0
        Rails.logger.info "[FetchContentJob] No content items need details filled. Skipping job."
        return 0
      end
      
      Rails.logger.info "[FetchContentJob] Found #{needs_update_count} items that need details filled."
      
      if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution] && !options['is_fallback_execution']
        Rails.logger.info "[FetchContentJob] Delegating fill_missing_details to job runner"
        
        # First wake up the job runner with retries
        unless JobRunnerService.wake_up_job_runner(max_retries: 2)
          Rails.logger.warn "[FetchContentJob] Failed to wake up job runner for fill_missing_details. Rescheduling..."
          reschedule_specific_job('fill_missing_details', options)
          return 0
        end
        
        # Add a flag to prevent infinite delegation loops
        options[:delegated_at] = Time.current.to_i
        
        job_id = JobRunnerService.run_specific_job('FetchContentJob', 'fill_missing_details', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated fill_missing_details to job runner. Job ID: #{job_id}"
          return 0
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate fill_missing_details to job runner. Rescheduling..."
          reschedule_specific_job('fill_missing_details', options)
          return 0
        end
      else
        Rails.logger.info "[FetchContentJob] Running fill_missing_details locally"
        return run_fill_missing_details_locally(options)
      end
    end
    
    private
    
    def reschedule_specific_job(method_name, options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      # Check if there are any items that need updating before rescheduling
      if method_name == 'fill_missing_details'
        needs_update_count = Content.where(tmdb_last_update: nil)
                                   .or(Content.where('tmdb_last_update < ?', 2.weeks.ago))
                                   .count
        
        if needs_update_count == 0
          Rails.logger.info "[FetchContentJob] No content items need details filled. Skipping rescheduling."
          return
        end
      end
      
      # Track reschedule attempts to prevent infinite loops
      reschedule_count = options[:reschedule_count].to_i || 0
      
      # Limit the number of reschedules to prevent infinite loops
      if reschedule_count >= 3
        Rails.logger.warn "[FetchContentJob] Job #{method_name} has been rescheduled #{reschedule_count} times. Stopping to prevent infinite loop."
        return
      end
      
      # Add a flag to indicate this is a fallback execution
      options = options.merge(
        is_fallback_execution: true,
        reschedule_count: reschedule_count + 1
      )
      
      # Schedule the job to run again in the future
      # Increase delay based on reschedule count to implement exponential backoff
      delay = (5 * (reschedule_count + 1)).minutes
      
      Rails.logger.info "[FetchContentJob] Rescheduling #{method_name} to run in #{delay / 60} minutes with options: #{options.inspect}"
      
      FetchContentJob.set(wait: delay).perform_later(options)
    end
    
    def run_fetch_new_content_locally(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      # Track start time locally to avoid nil reference
      start_time = Time.now
      
      Rails.logger.info "[FetchContentJob][New Content] Starting fetch"
      batch_size = options[:batch_size] || options['batch_size'] || 50
      max_items = options[:max_items] || options['max_items'] || 1000
      Rails.logger.info "[FetchContentJob][New Content] Using batch_size: #{batch_size}, max_items: #{max_items}"
      
      # Run the rake task
      begin
        # Ensure Rake is loaded
        require 'rake'
        
        # Load Rails application tasks if they haven't been loaded
        unless defined?(Rake::Task) && Rake::Task.task_defined?('tmdb:fetch_content')
          Rails.logger.info "[FetchContentJob][New Content] Loading Rake tasks"
          Rails.application.load_tasks
        end
        
        # Capture the output to count new items
        new_items_added = 0
        
        # Set up a hook to capture the "Total new items added" line
        original_puts = Kernel.method(:puts)
        Kernel.define_singleton_method(:puts) do |*args|
          message = args.first.to_s
          if message.include?("Total new items added:")
            # Extract the number of new items added
            match = message.match(/Total new items added: (\d+)/)
            new_items_added = match[1].to_i if match
          end
          original_puts.call(*args)
        end
        
        # Run the rake task
        Rake::Task['tmdb:fetch_content'].invoke
        Rake::Task['tmdb:fetch_content'].reenable
        
        # Restore original puts
        Kernel.singleton_class.send(:remove_method, :puts)
        Kernel.define_singleton_method(:puts, &original_puts)
        
        # Use local start_time instead of @job_start_time to avoid nil reference
        duration = Time.now - start_time
        Rails.logger.info "[FetchContentJob][New Content] Completed in #{duration.round(2)} seconds. Added #{new_items_added} new items."
        
        new_items_added
      rescue => e
        Rails.logger.error "[FetchContentJob][New Content] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Safely handle the error without trying to access nil objects
        if e.message.include?("uninitialized constant Rake::Task")
          Rails.logger.error "[FetchContentJob][New Content] Rake tasks not loaded. Try running 'Rails.application.load_tasks' first."
        end
        
        # Return 0 instead of re-raising to allow the job to continue
        0
      end
    end
    
    def run_update_existing_content_locally(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      # Track start time locally to avoid nil reference
      start_time = Time.now
      
      Rails.logger.info "[FetchContentJob][Update] Starting update of existing content"
      
      # Run the rake task
      begin
        # Ensure Rake is loaded
        require 'rake'
        
        # Load Rails application tasks if they haven't been loaded
        unless defined?(Rake::Task) && Rake::Task.task_defined?('tmdb:update_content')
          Rails.logger.info "[FetchContentJob][Update] Loading Rake tasks"
          Rails.application.load_tasks
        end
        
        # Capture the output to count significant changes
        significant_changes = 0
        
        # Set up a hook to capture the "Items with significant changes" line
        original_puts = Kernel.method(:puts)
        Kernel.define_singleton_method(:puts) do |*args|
          message = args.first.to_s
          if message.include?("Items with significant changes:")
            # Extract the number of items with significant changes
            match = message.match(/Items with significant changes: (\d+)/)
            significant_changes = match[1].to_i if match
          end
          original_puts.call(*args)
        end
        
        # Run the rake task
        Rake::Task['tmdb:update_content'].invoke
        Rake::Task['tmdb:update_content'].reenable
        
        # Restore original puts
        Kernel.singleton_class.send(:remove_method, :puts)
        Kernel.define_singleton_method(:puts, &original_puts)
        
        # Use local start_time instead of @job_start_time to avoid nil reference
        duration = Time.now - start_time
        Rails.logger.info "[FetchContentJob][Update] Completed in #{duration.round(2)} seconds. Updated #{significant_changes} items with significant changes."
        
        significant_changes
      rescue => e
        Rails.logger.error "[FetchContentJob][Update] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Safely handle the error without trying to access nil objects
        if e.message.include?("uninitialized constant Rake::Task")
          Rails.logger.error "[FetchContentJob][Update] Rake tasks not loaded. Try running 'Rails.application.load_tasks' first."
        end
        
        # Return 0 instead of re-raising to allow the job to continue
        0
      end
    end
    
    def run_fill_missing_details_locally(options = {})
      # Ensure options is a hash with indifferent access
      options = options.to_h if options.respond_to?(:to_h)
      options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
      
      # Track start time locally to avoid nil reference
      start_time = Time.current
      
      require 'rake'
      Rails.application.load_tasks
      
      batch_size = options[:batch_size] || options['batch_size'] || BATCH_SIZE
      max_items = options[:max_items] || options['max_items'] || MAX_ITEMS_PER_RUN
      
      Rails.logger.info "[FetchContentJob] Running fill_missing_details with batch_size: #{batch_size}, max_items: #{max_items}"
      
      # Check if we've been delegated too many times (potential infinite loop)
      if options[:delegated_at].present? && Time.current.to_i - options[:delegated_at].to_i > 3600
        Rails.logger.error "[FetchContentJob] Detected potential delegation loop. Job has been delegated for over an hour. Aborting."
        return 0
      end
      
      # Set environment variables for the Rake task
      ENV['BATCH_SIZE'] = batch_size.to_s
      ENV['MAX_ITEMS'] = max_items.to_s
      
      # Capture the output to count updated items
      updated_items = 0
      
      # Set up a hook to capture the "Total items updated" line
      original_puts = Kernel.method(:puts)
      Kernel.define_singleton_method(:puts) do |*args|
        message = args.first.to_s
        if message.include?("Total items updated:")
          # Extract the number of updated items
          match = message.match(/Total items updated: (\d+)/)
          updated_items = match[1].to_i if match
        end
        original_puts.call(*args)
      end
      
      # Run the Rake task
      begin
        Rake::Task['tmdb:fill_missing_details'].invoke
        Rake::Task['tmdb:fill_missing_details'].reenable
      rescue => e
        Rails.logger.error "[FetchContentJob] Error running fill_missing_details Rake task: #{e.message}\n#{e.backtrace.join("\n")}"
      end
      
      # Restore original puts
      Kernel.singleton_class.send(:remove_method, :puts)
      Kernel.define_singleton_method(:puts, &original_puts)
      
      # Use local start_time instead of @job_start_time to avoid nil reference
      duration = Time.current - start_time
      Rails.logger.info "[FetchContentJob] Completed in #{duration.round(2)} seconds. Updated #{updated_items} items."
      
      # If we updated items, don't reschedule immediately
      # This prevents continuous rescheduling when there are no more items to update
      if updated_items > 0
        Rails.logger.info "[FetchContentJob] Successfully updated #{updated_items} items. Next run will be scheduled by the system."
      else
        Rails.logger.info "[FetchContentJob] No items were updated. No need to reschedule."
      end
      
      updated_items
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
    # Ensure options is a hash with indifferent access
    options = options.to_h if options.respond_to?(:to_h)
    options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
    
    # For full content fetches or updates, we should reschedule rather than run on main app
    # For smaller operations, we can run locally as fallback
    options.empty? || options[:fetch_new] || options['fetch_new'] || options[:update_existing] || options['update_existing']
  end
  
  def reschedule_job(options = {})
    # Ensure options is a hash with indifferent access
    options = options.to_h if options.respond_to?(:to_h)
    options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
    
    # Add a flag to indicate this is a fallback execution
    options = options.merge(is_fallback_execution: true)
    
    # Schedule the job to run again in the future
    delay = 5.minutes
    
    Rails.logger.info "[FetchContentJob] Rescheduling job to run in #{delay / 60} minutes with options: #{options.inspect}"
    
    FetchContentJob.set(wait: delay).perform_later(options)
  end

  def update_existing_content(options = {})
    # Ensure options is a hash with indifferent access
    options = options.to_h if options.respond_to?(:to_h)
    options = options.with_indifferent_access if options.respond_to?(:with_indifferent_access)
    
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production? && !options[:is_fallback_execution] && !options['is_fallback_execution']
      Rails.logger.info "[FetchContentJob][Update] Starting update of existing content"
      start_time = Time.now
      
      # Run the rake task
      begin
        # Ensure Rake is loaded
        require 'rake'
        
        # Load Rails application tasks if they haven't been loaded
        unless defined?(Rake::Task) && Rake::Task.task_defined?('tmdb:update_content')
          Rails.logger.info "[FetchContentJob][Update] Loading Rake tasks"
          Rails.application.load_tasks
        end
        
        # Capture the output to count significant changes
        significant_changes = 0
        
        # Set up a hook to capture the "Items with significant changes" line
        original_puts = Kernel.method(:puts)
        Kernel.define_singleton_method(:puts) do |*args|
          message = args.first.to_s
          if message.include?("Items with significant changes:")
            # Extract the number of items with significant changes
            match = message.match(/Items with significant changes: (\d+)/)
            significant_changes = match[1].to_i if match
          end
          original_puts.call(*args)
        end
        
        # Run the rake task
        Rake::Task['tmdb:update_content'].invoke
        Rake::Task['tmdb:update_content'].reenable
        
        # Restore original puts
        Kernel.singleton_class.send(:remove_method, :puts)
        Kernel.define_singleton_method(:puts, &original_puts)
        
        duration = Time.now - start_time
        Rails.logger.info "[FetchContentJob][Update] Completed in #{duration.round(2)} seconds. Updated #{significant_changes} items with significant changes."
        
        significant_changes
      rescue => e
        Rails.logger.error "[FetchContentJob][Update] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Safely handle the error without trying to access nil objects
        if e.message.include?("uninitialized constant Rake::Task")
          Rails.logger.error "[FetchContentJob][Update] Rake tasks not loaded. Try running 'Rails.application.load_tasks' first."
        end
        
        # Re-raise the error to be handled by the job's error handling
        raise e
      end
    end
  end

  # Add the instance method to call the class method
  def fetch_new_content(options = {})
    self.class.fetch_new_content(options)
  end

  # Add the instance method to call the class method
  def fill_missing_details(options = {})
    self.class.fill_missing_details(options)
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
