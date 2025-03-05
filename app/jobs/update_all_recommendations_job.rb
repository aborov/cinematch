require 'httparty'

class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    # Ensure options is a regular hash
    options = options.to_h if options.respond_to?(:to_h)
    batch_size = options[:batch_size] || 50
    
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production?
      Rails.logger.info "[UpdateAllRecommendationsJob] Running in production on main app, delegating to job runner service"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('UpdateAllRecommendationsJob', { batch_size: batch_size })
        
        if job_id
          Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to delegate to job runner. Running locally instead."
        end
      end
    else
      Rails.logger.info "[UpdateAllRecommendationsJob] Running on job runner or in development, executing locally"
    end
    
    Rails.logger.info "[UpdateAllRecommendationsJob] Starting to update recommendations for all users"
    start_time = Time.current
    
    # Process all users in a single job using the RecommendationService
    if ENV['JOB_RUNNER_ONLY'] == 'true' && ENV['MAIN_APP_URL'].present? && Rails.env.production?
      # If we're on the job runner, we need to notify the main app to generate recommendations
      # This is a special case where we need to delegate back to the main app
      # because the job runner might not have access to all the data needed for recommendations
      begin
        # Use a dedicated shared secret for job runner authentication
        shared_secret = ENV['JOB_RUNNER_SECRET'] || ENV['SECRET_KEY_BASE'].to_s[0..15]
        
        Rails.logger.info "[UpdateAllRecommendationsJob] Delegating recommendations generation to main app"
        response = HTTParty.post(
          "#{ENV['MAIN_APP_URL']}/api/job_runner/run_job",
          body: {
            job_class: 'ProcessAllRecommendationsJob',
            args: { batch_size: batch_size },
            secret: shared_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' },
          timeout: 15
        )
        
        if response.success?
          Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated recommendations generation to main app"
        else
          Rails.logger.error "[UpdateAllRecommendationsJob] Failed to delegate to main app: #{response.code} - #{response.body}"
          # Fall back to running locally
          process_locally(batch_size)
        end
      rescue => e
        Rails.logger.error "[UpdateAllRecommendationsJob] Failed to delegate to main app: #{e.message}"
        # Fall back to running locally
        process_locally(batch_size)
      end
    else
      # Otherwise, process locally
      process_locally(batch_size)
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[UpdateAllRecommendationsJob] Completed updating recommendations for all users in #{duration.round(2)}s"
  end
  
  private
  
  def process_locally(batch_size)
    Rails.logger.info "[UpdateAllRecommendationsJob] Processing all recommendations locally with batch size #{batch_size}"
    
    # Force garbage collection before processing
    GC.start
    
    begin
      result = RecommendationService.generate_for_all_users(batch_size: batch_size)
      
      Rails.logger.info "[UpdateAllRecommendationsJob] Successfully processed recommendations for #{result[:successful_users]} users"
      if result[:failed_users] > 0
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to process recommendations for #{result[:failed_users]} users"
      end
    rescue => e
      Rails.logger.error "[UpdateAllRecommendationsJob] Error processing recommendations: #{e.message}\n#{e.backtrace.join("\n")}"
    ensure
      # Force garbage collection after processing
      GC.start
    end
  end
  
  # Class method for direct invocation
  def self.update_all_recommendations(options = {})
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production?
      Rails.logger.info "[UpdateAllRecommendationsJob] Delegating update_all_recommendations to job runner"
      JobRunnerService.wake_up_job_runner
      job_id = JobRunnerService.run_specific_job('UpdateAllRecommendationsJob', 'update_all_recommendations', options)
      
      if job_id
        Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated update_all_recommendations to job runner. Job ID: #{job_id}"
      else
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to delegate to job runner. Running locally instead."
        new.perform(options)
      end
    else
      Rails.logger.info "[UpdateAllRecommendationsJob] Running update_all_recommendations locally"
      new.perform(options)
    end
  end
end
