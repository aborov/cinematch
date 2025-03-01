class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    # If we're not on the job runner instance and the job runner URL is configured,
    # delegate the job to the job runner service
    if !ENV['JOB_RUNNER_ONLY'] && ENV['JOB_RUNNER_URL'].present?
      Rails.logger.info "[FetchContentJob] Delegating to job runner service"
      job_id = JobRunnerService.run_job('FetchContentJob', options)
      
      if job_id
        Rails.logger.info "[FetchContentJob] Successfully delegated to job runner. Job ID: #{job_id}"
        return
      else
        Rails.logger.warn "[FetchContentJob] Failed to delegate to job runner. Running locally instead."
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
    if ENV['JOB_RUNNER_ONLY'] && ENV['MAIN_APP_URL'].present?
      # If we're on the job runner, we need to notify the main app to update recommendations
      Rails.logger.info "[FetchContentJob] Notifying main app to update recommendations"
      begin
        HTTP.timeout(30).post(
          "#{ENV['MAIN_APP_URL']}/api/run_job",
          json: {
            job_class: 'UpdateAllRecommendationsJob',
            secret: ENV['SECRET_KEY_BASE'].to_s[0..15]
          }
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
