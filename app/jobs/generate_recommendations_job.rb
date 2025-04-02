class GenerateRecommendationsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(user_id)
    begin
      user = User.find(user_id)
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn "GenerateRecommendationsJob: User with ID #{user_id} not found. Skipping job."
      return # Exit the job gracefully
    end
    user_recommendation = user.ensure_user_recommendation
    Rails.logger.info "Starting recommendation generation for user #{user_id}"
    
    begin
      user_recommendation.generate_recommendations
    rescue => e
      Rails.logger.error "Failed to generate recommendations: #{e.message}"
      user_recommendation.update(processing: false)
      raise
    end
  end
end
