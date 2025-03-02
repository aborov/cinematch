class GenerateRecommendationsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(args = {})
    # Ensure args is a regular hash
    args = args.to_h if args.respond_to?(:to_h)
    
    user_id = args[:user_id] || args
    
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true'
      Rails.logger.info "[GenerateRecommendationsJob] Delegating to job runner service for user #{user_id}"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[GenerateRecommendationsJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('GenerateRecommendationsJob', { user_id: user_id })
        
        if job_id
          Rails.logger.info "[GenerateRecommendationsJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[GenerateRecommendationsJob] Failed to delegate to job runner. Running locally instead."
        end
      end
    end
    
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.error "[GenerateRecommendationsJob] User #{user_id} not found"
      return
    end

    Rails.logger.info "[GenerateRecommendationsJob] Generating recommendations for user #{user_id}"
    start_time = Time.current

    # Force garbage collection before processing
    GC.start

    begin
      RecommendationService.generate_for_user(user)
      duration = Time.current - start_time
      Rails.logger.info "[GenerateRecommendationsJob] Successfully generated recommendations for user #{user_id} in #{duration.round(2)}s"
    rescue => e
      Rails.logger.error "[GenerateRecommendationsJob] Failed to generate recommendations for user #{user_id}: #{e.message}\n#{e.backtrace.join("\n")}"
    ensure
      # Force garbage collection after processing
      GC.start
    end
  end
  
  # Class method for direct invocation
  def self.generate_recommendations_for_user(args = {})
    # Ensure args is a regular hash
    args = args.to_h if args.respond_to?(:to_h)
    
    user_id = args[:user_id] || args
    
    if ENV['JOB_RUNNER_ONLY'] != 'true'
      Rails.logger.info "[GenerateRecommendationsJob] Delegating generate_recommendations_for_user to job runner for user #{user_id}"
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_specific_job('GenerateRecommendationsJob', 'generate_recommendations_for_user', { user_id: user_id })
    else
      Rails.logger.info "[GenerateRecommendationsJob] Running generate_recommendations_for_user locally for user #{user_id}"
      new.perform(user_id: user_id)
    end
  end
end
