class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform
    UserPreference.find_each(batch_size: 50) do |user_preference|
      GenerateRecommendationsJob.perform_later(user_preference.id)
    end
  end
end
