class UpdateAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform
    # Instead of enqueuing all jobs at once, process in smaller batches
    User.find_each(batch_size: 2) do |user|
      GenerateRecommendationsJob.set(wait: 5.seconds).perform_later(user.id)
    end
  end
end
