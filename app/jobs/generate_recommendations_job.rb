class GenerateRecommendationsJob < ApplicationJob
  queue_as :default

  def perform(user_preference_id)
    user_preference = UserPreference.find(user_preference_id)
    user_preference.generate_recommendations
  end
end
