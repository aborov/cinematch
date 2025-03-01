class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true'
      Rails.logger.info "[UpdateAllRecommendationsJob] Delegating to job runner service"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('UpdateAllRecommendationsJob')
        
        if job_id
          Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to delegate to job runner. Running locally instead."
        end
      end
    end
    
    Rails.logger.info "[UpdateAllRecommendationsJob] Starting to update recommendations for all users"
    start_time = Time.current
    
    # Instead of enqueuing all jobs at once, process in smaller batches
    user_count = 0
    User.find_each(batch_size: 5) do |user|
      user_count += 1
      if ENV['JOB_RUNNER_ONLY'] == 'true' && ENV['MAIN_APP_URL'].present?
        # If we're on the job runner, we need to notify the main app to generate recommendations
        begin
          Rails.logger.info "[UpdateAllRecommendationsJob] Delegating recommendations for user #{user.id} to main app"
          HTTParty.post(
            "#{ENV['MAIN_APP_URL']}/api/job_runner/run_job",
            body: {
              job_class: 'GenerateRecommendationsJob',
              args: { user_id: user.id },
              secret: ENV['SECRET_KEY_BASE'].to_s[0..15]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
          sleep(2) # Add a delay to prevent overwhelming the main app
        rescue => e
          Rails.logger.error "[UpdateAllRecommendationsJob] Failed to notify main app for user #{user.id}: #{e.message}"
          # Fall back to running locally
          GenerateRecommendationsJob.set(wait: 5.seconds).perform_later(user_id: user.id)
        end
      else
        # Otherwise, schedule it locally
        Rails.logger.info "[UpdateAllRecommendationsJob] Scheduling recommendations for user #{user.id} locally"
        GenerateRecommendationsJob.set(wait: 2.seconds).perform_later(user_id: user.id)
      end
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[UpdateAllRecommendationsJob] Completed scheduling recommendations for #{user_count} users in #{duration.round(2)}s"
  end
  
  # Class method for direct invocation
  def self.update_all_recommendations
    if ENV['JOB_RUNNER_ONLY'] != 'true'
      Rails.logger.info "[UpdateAllRecommendationsJob] Delegating update_all_recommendations to job runner"
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_specific_job('UpdateAllRecommendationsJob', 'update_all_recommendations')
    else
      Rails.logger.info "[UpdateAllRecommendationsJob] Running update_all_recommendations locally"
      new.perform
    end
  end
end
