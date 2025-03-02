require 'httparty'

class FetchContentJob < ApplicationJob
  queue_as :default

  # Set a flag to track if this job is a retry after job runner failure
  attr_accessor :is_fallback_execution

  def perform(options = {})
    # Ensure options is a regular hash
    options = options.to_h if options.respond_to?(:to_h)
    @is_fallback_execution = options.delete(:is_fallback_execution) || false
    
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
    
    if options[:fetch_new] || options.empty?
      Rails.logger.info "[FetchContentJob] Daily content fetch - Started at #{@start_time.strftime('%H:%M:%S')}"
      fetch_new_content
    end
    
    if options[:update_existing] || options.empty?
      Rails.logger.info "[FetchContentJob] Bi-weekly content update - Started at #{@start_time.strftime('%H:%M:%S')}"
      update_existing_content
    end
    
    if options[:fill_missing] || options.empty?
      Rails.logger.info "[FetchContentJob] Missing details fill - Started at #{@start_time.strftime('%H:%M:%S')}"
      fill_missing_details
    end
    
    duration = Time.current - @start_time
    Rails.logger.info "[FetchContentJob] Job completed in #{duration.round(2)}s. Total content items: #{Content.count}"
    
    # Schedule the recommendations update job
    if ENV['JOB_RUNNER_ONLY'] == 'true' && ENV['MAIN_APP_URL'].present?
      # If we're on the job runner, we need to notify the main app to update recommendations
      Rails.logger.info "[FetchContentJob] Notifying main app to update recommendations"
      begin
        # Use a dedicated shared secret for job runner authentication
        shared_secret = ENV['JOB_RUNNER_SECRET'] || ENV['SECRET_KEY_BASE'].to_s[0..15]
        
        max_retries = 2
        retry_count = 0
        
        begin
          response = HTTParty.post(
            "#{ENV['MAIN_APP_URL']}/api/job_runner/run_job",
            body: {
              job_class: 'UpdateAllRecommendationsJob',
              secret: shared_secret
            }.to_json,
            headers: { 'Content-Type' => 'application/json' },
            timeout: 15
          )
          
          if response.success?
            Rails.logger.info "[FetchContentJob] Successfully notified main app to update recommendations"
          else
            error_message = "[FetchContentJob] Failed to notify main app: #{response.code} - #{response.body}"
            
            if retry_count < max_retries && (response.code >= 500 || response.code == 0)
              retry_count += 1
              Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
              sleep(2 * retry_count) # Exponential backoff
              retry
            end
            
            Rails.logger.error error_message
            # Fall back to running locally
            UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
          end
        rescue => e
          error_message = "[FetchContentJob] Failed to notify main app: #{e.message}"
          
          if retry_count < max_retries
            retry_count += 1
            Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
            sleep(2 * retry_count) # Exponential backoff
            retry
          end
          
          Rails.logger.error error_message
          # Fall back to running locally
          UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
        end
      rescue => e
        Rails.logger.error "[FetchContentJob] Unexpected error notifying main app: #{e.message}"
        # Fall back to running locally
        UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
      end
    else
      # Otherwise, schedule it locally
      Rails.logger.info "[FetchContentJob] Scheduling recommendations update locally"
      UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
    end
  rescue => e
    Rails.logger.error "[FetchContentJob] Failed after #{(Time.current - @start_time).round(2)}s: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
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
        run_fetch_new_content_locally
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
        run_update_existing_content_locally
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
        run_fill_missing_details_locally
      end
    end
    
    private
    
    def reschedule_specific_job(method_name, options = {})
      # Add a flag to indicate this is a fallback execution
      options = options.merge(is_fallback_execution: true)
      
      # Reschedule the job with exponential backoff
      retry_count = options[:retry_count].to_i
      
      if retry_count < 5
        delay = [5, 15, 30, 60, 120][retry_count] # 5s, 15s, 30s, 1m, 2m
        options[:retry_count] = retry_count + 1
        
        Rails.logger.info "[FetchContentJob] Rescheduling #{method_name} to run in #{delay} seconds (attempt #{retry_count + 1}/5)"
        FetchContentJob.set(wait: delay.seconds).public_send(method_name, options)
      else
        # After 5 retries, run locally as fallback
        Rails.logger.warn "[FetchContentJob] Maximum retries reached for #{method_name}. Running locally as fallback."
        FetchContentJob.public_send("run_#{method_name}_locally")
      end
    end
    
    def run_fetch_new_content_locally
      require 'rake'
      Rails.application.load_tasks
      Rake::Task['tmdb:fetch_content'].invoke
      Rake::Task['tmdb:fetch_content'].reenable
    end
    
    def run_update_existing_content_locally
      require 'rake'
      Rails.application.load_tasks
      Rake::Task['tmdb:update_content'].invoke
      Rake::Task['tmdb:update_content'].reenable
    end
    
    def run_fill_missing_details_locally
      require 'rake'
      Rails.application.load_tasks
      Rake::Task['tmdb:fill_missing_details'].invoke
      Rake::Task['tmdb:fill_missing_details'].reenable
    end
  end

  private
  
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
      delay = [5, 15, 30, 60, 120][retry_count] # 5s, 15s, 30s, 1m, 2m
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

  def fetch_new_content
    Rails.logger.info "[FetchContentJob][New Content] Starting fetch"
    Rake::Task['tmdb:fetch_content'].invoke
    Rake::Task['tmdb:fetch_content'].reenable
  end

  def update_existing_content
    Rails.logger.info "[FetchContentJob][Update] Starting update of existing content"
    Rake::Task['tmdb:update_content'].invoke
    Rake::Task['tmdb:update_content'].reenable
  end

  def fill_missing_details
    Rails.logger.info "[FetchContentJob][Fill Missing] Starting missing details fill"
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
  end
end
