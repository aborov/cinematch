class GenerateRecommendationsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(user_id)
    user = User.find(user_id)
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
