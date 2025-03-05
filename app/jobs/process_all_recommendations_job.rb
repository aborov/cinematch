class ProcessAllRecommendationsJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    # Ensure options is a regular hash
    options = options.to_h if options.respond_to?(:to_h)
    batch_size = options[:batch_size] || 50
    
    Rails.logger.info "[ProcessAllRecommendationsJob] Starting to process recommendations for all users"
    start_time = Time.current
    
    # Use the RecommendationService to generate recommendations for all users
    begin
      result = RecommendationService.generate_for_all_users(batch_size: batch_size)
      
      Rails.logger.info "[ProcessAllRecommendationsJob] Successfully processed recommendations for #{result[:successful_users]} users"
      if result[:failed_users] > 0
        Rails.logger.warn "[ProcessAllRecommendationsJob] Failed to process recommendations for #{result[:failed_users]} users"
      end
    rescue => e
      Rails.logger.error "[ProcessAllRecommendationsJob] Error processing recommendations: #{e.message}\n#{e.backtrace.join("\n")}"
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[ProcessAllRecommendationsJob] Completed processing recommendations in #{duration.round(2)}s"
  end
end 
