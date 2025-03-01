class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform
    # If we're not on the job runner instance and the job runner URL is configured,
    # delegate the job to the job runner service
    if !ENV['JOB_RUNNER_ONLY'] && ENV['JOB_RUNNER_URL'].present?
      Rails.logger.info "[UpdateAllRecommendationsJob] Delegating to job runner service"
      job_id = JobRunnerService.run_job('UpdateAllRecommendationsJob')
      
      if job_id
        Rails.logger.info "[UpdateAllRecommendationsJob] Successfully delegated to job runner. Job ID: #{job_id}"
        return
      else
        Rails.logger.warn "[UpdateAllRecommendationsJob] Failed to delegate to job runner. Running locally instead."
      end
    end
    
    # Instead of enqueuing all jobs at once, process in smaller batches
    User.find_each(batch_size: 2) do |user|
      if ENV['JOB_RUNNER_ONLY'] && ENV['MAIN_APP_URL'].present?
        # If we're on the job runner, we need to notify the main app to generate recommendations
        begin
          HTTP.timeout(30).post(
            "#{ENV['MAIN_APP_URL']}/api/run_job",
            json: {
              job_class: 'GenerateRecommendationsJob',
              args: { user_id: user.id },
              secret: ENV['SECRET_KEY_BASE'].to_s[0..15]
            }
          )
          sleep(5) # Add a delay to prevent overwhelming the main app
        rescue => e
          Rails.logger.error "[UpdateAllRecommendationsJob] Failed to notify main app for user #{user.id}: #{e.message}"
          # Fall back to running locally
          GenerateRecommendationsJob.set(wait: 5.seconds).perform_later(user.id)
        end
      else
        # Otherwise, schedule it locally
        GenerateRecommendationsJob.set(wait: 5.seconds).perform_later(user.id)
      end
    end
  end
end
