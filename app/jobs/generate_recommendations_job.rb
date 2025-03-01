class GenerateRecommendationsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(user_id)
    # If we're not on the job runner instance and the job runner URL is configured,
    # delegate the job to the job runner service
    if !ENV['JOB_RUNNER_ONLY'] && ENV['JOB_RUNNER_URL'].present?
      Rails.logger.info "[GenerateRecommendationsJob] Delegating to job runner service for user #{user_id}"
      job_id = JobRunnerService.run_job('GenerateRecommendationsJob', { user_id: user_id })
      
      if job_id
        Rails.logger.info "[GenerateRecommendationsJob] Successfully delegated to job runner. Job ID: #{job_id}"
        return
      else
        Rails.logger.warn "[GenerateRecommendationsJob] Failed to delegate to job runner. Running locally instead."
      end
    end
    
    user = User.find_by(id: user_id)
    return unless user

    # Force garbage collection before processing
    GC.start

    begin
      user_recommendation.generate_recommendations
    rescue => e
      Rails.logger.error "Failed to generate recommendations: #{e.message}"
      user_recommendation.update(processing: false)
      raise
    end
  end
end
