class GenerateRecommendationsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(user_preference_id)
    user_preference = UserPreference.find(user_preference_id)
    Rails.logger.info "Starting recommendation generation for user #{user_preference.user_id}"
    
    begin
      user_preference.generate_recommendations
    rescue => e
      Rails.logger.error "Failed to generate recommendations: #{e.message}"
      user_preference.update(processing: false)
      raise
    end
  end
end
