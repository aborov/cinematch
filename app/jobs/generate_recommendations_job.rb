class GenerateRecommendationsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    # Force garbage collection before processing
    GC.start

    begin
      RecommendationService.generate_for_user(user)
    rescue => e
      Rails.logger.error("Failed to generate recommendations for user #{user_id}: #{e.message}")
    ensure
      # Force garbage collection after processing
      GC.start
    end
  end
end
