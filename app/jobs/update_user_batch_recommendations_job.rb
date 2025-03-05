class UpdateUserBatchRecommendationsJob < ApplicationJob
  queue_as :recommendations

  def perform(user_ids)
    Rails.logger.info "[UpdateUserBatchRecommendationsJob] Starting to process recommendations for batch of #{user_ids.size} users"
    start_time = Time.current
    
    successful = 0
    failed = 0
    
    User.where(id: user_ids).find_each do |user|
      begin
        RecommendationService.generate_for_user(user)
        successful += 1
      rescue => e
        failed += 1
        Rails.logger.error "[UpdateUserBatchRecommendationsJob] Failed to generate recommendations for user #{user.id}: #{e.message}"
      end
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[UpdateUserBatchRecommendationsJob] Completed processing recommendations for batch: #{successful} successful, #{failed} failed in #{duration.round(2)}s"
  end
end 
