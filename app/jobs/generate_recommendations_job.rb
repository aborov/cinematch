class GenerateRecommendationsJob < ApplicationJob
  queue_as :default

  # Custom error class for job cancellation
  class JobCancellationError < StandardError; end

  def perform(user_id)
    # Store the job ID for cancellation checks
    @job_id = provider_job_id
    
    # Check for cancellation before starting
    if cancelled?
      Rails.logger.info "Job #{@job_id} was cancelled before starting"
      return
    end
    
    begin
      user = User.find(user_id)
      
      # Force garbage collection before starting
      GC.start(full_mark: true, immediate_sweep: true)
      
      Rails.logger.info "Generating recommendations for user #{user.id}"
      
      # Check for cancellation before generating recommendations
      check_cancellation
      
      RecommendationService.generate_recommendations_for(user)
      Rails.logger.info "Completed generating recommendations for user #{user.id}"
    rescue JobCancellationError => e
      Rails.logger.info "Job was cancelled: #{e.message}"
      # No need to re-raise, just let the job end
    rescue => e
      Rails.logger.error "Error generating recommendations for user #{user_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    ensure
      # Force garbage collection after completion
      GC.start(full_mark: true, immediate_sweep: true)
    end
  end
  
  private
  
  # Check if the job has been cancelled
  def cancelled?
    return false unless @job_id
    cancelled = JobCancellationService.cancelled?(@job_id)
    Rails.logger.info "Job #{@job_id} cancellation check: #{cancelled}" if cancelled
    cancelled
  end
  
  # Check for cancellation and raise an error if cancelled
  def check_cancellation
    if cancelled?
      Rails.logger.info "Job #{@job_id} was cancelled during processing"
      raise JobCancellationError, "Job was cancelled by user"
    end
  end
end
