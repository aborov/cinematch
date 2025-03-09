require 'httparty'

class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :recommendations

  # Constants for batch processing
  BATCH_SIZE = 50
  USER_BATCH_SIZE = 20
  MAX_RETRIES = 3

  def perform(options = {})
    # Handle both array and hash formats for options
    if options.is_a?(Array) && options.length >= 2 && options.length.even?
      # Convert array format [:key1, value1, :key2, value2] to hash {key1: value1, key2: value2}
      options_hash = {}
      options.each_slice(2) do |key, value|
        options_hash[key.to_sym] = value if key.respond_to?(:to_sym)
      end
      options = options_hash
    end
    
    # Ensure options is a regular hash
    options = options.to_h if options.respond_to?(:to_h)
    batch_size = options[:batch_size] || options['batch_size'] || BATCH_SIZE
    user_batch_size = options[:user_batch_size] || options['user_batch_size'] || USER_BATCH_SIZE
    
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production?
      Rails.logger.info "[UpdateAllRecommendationsJob] Running in production on main app, delegating to job runner service"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('UpdateAllRecommendationsJob', { 
          batch_size: batch_size,
          user_batch_size: user_batch_size
        })
        
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
            args: { 
              batch_size: batch_size,
              user_batch_size: user_batch_size
            },
            secret: shared_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' },
          timeout: 15
        )
        
        if response.success?
          Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated recommendations generation to main app"
        else
          Rails.logger.error "[UpdateAllRecommendationsJob] Failed to delegate recommendations generation to main app: #{response.code} - #{response.body}"
          # Fall back to running locally
          process_recommendations_locally(batch_size, user_batch_size)
        end
      rescue => e
        Rails.logger.error "[UpdateAllRecommendationsJob] Error delegating recommendations generation to main app: #{e.message}"
        # Fall back to running locally
        process_recommendations_locally(batch_size, user_batch_size)
      end
    else
      # Process recommendations locally
      process_recommendations_locally(batch_size, user_batch_size)
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[UpdateAllRecommendationsJob] Completed in #{duration.round(2)}s"
  end
  
  private
  
  def process_recommendations_locally(batch_size, user_batch_size)
    Rails.logger.info "[UpdateAllRecommendationsJob] Processing recommendations locally with batch_size: #{batch_size}, user_batch_size: #{user_batch_size}"
    
    # Use the RecommendationService to generate recommendations for all users
    begin
      # Count total users for progress tracking
      total_users = User.count
      processed_users = 0
      successful_batches = 0
      failed_batches = 0
      
      # Process users in batches
      User.find_in_batches(batch_size: batch_size) do |users_batch|
        batch_start_time = Time.current
        batch_user_ids = users_batch.map(&:id)
        
        begin
          # Process this batch of users
          UpdateUserBatchRecommendationsJob.perform_now(batch_user_ids, { batch_size: user_batch_size })
          successful_batches += 1
        rescue => e
          failed_batches += 1
          Rails.logger.error "[UpdateAllRecommendationsJob] Error processing batch: #{e.message}\n#{e.backtrace.join("\n")}"
        ensure
          processed_users += batch_user_ids.size
          percent_complete = (processed_users.to_f / total_users * 100).round(1)
          
          batch_duration = Time.current - batch_start_time
          Rails.logger.info "[UpdateAllRecommendationsJob] Processed batch of #{batch_user_ids.size} users in #{batch_duration.round(2)}s (#{percent_complete}% complete)"
          
          # Force garbage collection between batches to manage memory
          GC.start
        end
      end
      
      Rails.logger.info "[UpdateAllRecommendationsJob] Successfully processed #{successful_batches} batches (#{failed_batches} failed)"
    rescue => e
      Rails.logger.error "[UpdateAllRecommendationsJob] Error processing recommendations: #{e.message}\n#{e.backtrace.join("\n")}"
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
