class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true'
      Rails.logger.info "[FetchContentJob] Delegating to job runner service"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[FetchContentJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('FetchContentJob', options)
        
        if job_id
          Rails.logger.info "[FetchContentJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[FetchContentJob] Failed to delegate to job runner. Running locally instead."
        end
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
        HTTParty.post(
          "#{ENV['MAIN_APP_URL']}/api/job_runner/run_job",
          body: {
            job_class: 'UpdateAllRecommendationsJob',
            secret: ENV['SECRET_KEY_BASE'].to_s[0..15]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      rescue => e
        Rails.logger.error "[FetchContentJob] Failed to notify main app: #{e.message}"
        # Fall back to running locally
        UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
      end
    else
      # Otherwise, schedule it locally
      UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
    end
  rescue => e
    Rails.logger.error "[FetchContentJob] Failed after #{(Time.current - @start_time).round(2)}s: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end

  # Class methods for direct invocation
  class << self
    def fetch_new_content(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true'
        Rails.logger.info "[FetchContentJob] Delegating fetch_new_content to job runner"
        JobRunnerService.wake_up_job_runner
        JobRunnerService.run_specific_job('FetchContentJob', 'fetch_new_content', options)
      else
        Rails.logger.info "[FetchContentJob] Running fetch_new_content locally"
        require 'rake'
        Rails.application.load_tasks
        Rake::Task['tmdb:fetch_content'].invoke
        Rake::Task['tmdb:fetch_content'].reenable
      end
    end
    
    def update_existing_content(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true'
        Rails.logger.info "[FetchContentJob] Delegating update_existing_content to job runner"
        JobRunnerService.wake_up_job_runner
        JobRunnerService.run_specific_job('FetchContentJob', 'update_existing_content', options)
      else
        Rails.logger.info "[FetchContentJob] Running update_existing_content locally"
        require 'rake'
        Rails.application.load_tasks
        Rake::Task['tmdb:update_content'].invoke
        Rake::Task['tmdb:update_content'].reenable
      end
    end
    
    def fill_missing_details(options = {})
      if ENV['JOB_RUNNER_ONLY'] != 'true'
        Rails.logger.info "[FetchContentJob] Delegating fill_missing_details to job runner"
        JobRunnerService.wake_up_job_runner
        JobRunnerService.run_specific_job('FetchContentJob', 'fill_missing_details', options)
      else
        Rails.logger.info "[FetchContentJob] Running fill_missing_details locally"
        require 'rake'
        Rails.application.load_tasks
        Rake::Task['tmdb:fill_missing_details'].invoke
        Rake::Task['tmdb:fill_missing_details'].reenable
      end
    end
  end

  private

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
