class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform
    UserPreference.find_each do |user_preference|
      user_preference.generate_recommendations
    end
  end
end
