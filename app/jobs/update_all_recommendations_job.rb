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
      # Instead of using RecommendationService.generate_for_all_users which processes users sequentially,
      # we'll process users in parallel batches for better performance
      
      # Get total number of users
      total_users = User.count
      Rails.logger.info "[UpdateAllRecommendationsJob] Found #{total_users} users to process"
      
      # Process users in batches, but create separate jobs for each batch
      # to allow for parallel processing
      successful_users = 0
      failed_users = 0
      
      # Use a smaller batch size for better parallelization
      actual_batch_size = [batch_size, 20].min
      
      User.find_in_batches(batch_size: actual_batch_size) do |users_batch|
        batch_start_time = Time.current
        batch_ids = users_batch.map(&:id)
        
        Rails.logger.info "[UpdateAllRecommendationsJob] Scheduling batch of #{batch_ids.size} users"
        
        # Create a job for this batch
        if Rails.env.production?
          # In production, use a separate job for each batch
          UpdateUserBatchRecommendationsJob.perform_later(batch_ids)
        else
          # In development, process synchronously for easier debugging
          batch_result = process_user_batch(batch_ids)
          successful_users += batch_result[:successful]
          failed_users += batch_result[:failed]
        end
        
        batch_duration = Time.current - batch_start_time
        Rails.logger.info "[UpdateAllRecommendationsJob] Completed scheduling recommendations for #{batch_ids.size} users in #{batch_duration.round(2)}s"
      end
      
      Rails.logger.info "[UpdateAllRecommendationsJob] Successfully scheduled recommendation updates for all users"
      
      if !Rails.env.production?
        Rails.logger.info "[UpdateAllRecommendationsJob] Summary: #{successful_users} successful, #{failed_users} failed"
      end
    rescue => e
      Rails.logger.error "[UpdateAllRecommendationsJob] Error processing recommendations: #{e.message}\n#{e.backtrace.join("\n")}"
    ensure
      # Force garbage collection after processing
      GC.start
    end
  end
  
  # Process a batch of users
  def process_user_batch(user_ids)
    successful = 0
    failed = 0
    
    User.where(id: user_ids).find_each do |user|
      begin
        RecommendationService.generate_for_user(user)
        successful += 1
      rescue => e
        failed += 1
        Rails.logger.error "[UpdateAllRecommendationsJob] Failed to generate recommendations for user #{user.id}: #{e.message}"
      end
    end
    
    { successful: successful, failed: failed }
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
