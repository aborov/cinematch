class UpdateUserBatchRecommendationsJob < ApplicationJob
  queue_as :recommendations

  # Constants for batch processing
  BATCH_SIZE = 20
  MAX_RETRIES = 3
  
  # Add discard_on to prevent retrying jobs that will never succeed
  discard_on ActiveRecord::RecordNotFound

  def perform(user_ids, options = {})
    options = options.to_h if options.respond_to?(:to_h)
    
    # Extract options with defaults
    batch_size = options[:batch_size] || options['batch_size'] || BATCH_SIZE
    
    Rails.logger.info "[UpdateUserBatchRecommendationsJob] Starting to process recommendations for batch of #{user_ids.size} users"
    start_time = Time.current
    
    successful = 0
    failed = 0
    skipped = 0
    
    # Ensure we have a clean connection state
    ActiveRecord::Base.connection_pool.with_connection do
      # Process users in smaller sub-batches to manage memory better
      user_ids.each_slice(batch_size) do |sub_batch_ids|
        sub_batch_start = Time.current
        
        begin
          # Preload user preferences for this sub-batch to reduce database queries
          user_preferences = UserPreference.where(user_id: sub_batch_ids).index_by(&:user_id)
          
          User.where(id: sub_batch_ids).find_each do |user|
            begin
              # Skip users who had recommendations generated recently (within last 24 hours)
              # unless forced refresh is requested
              user_preference = user_preferences[user.id] || user.ensure_user_preference
              
              if !options[:force] && !options['force'] && 
                 user_preference.recommendations_generated_at.present? && 
                 user_preference.recommendations_generated_at > 24.hours.ago
                
                skipped += 1
                next
              end
              
              # Generate recommendations with retry logic
              retry_count = 0
              begin
                RecommendationService.generate_for_user(user)
                successful += 1
              rescue => e
                retry_count += 1
                if retry_count <= MAX_RETRIES
                  Rails.logger.warn "[UpdateUserBatchRecommendationsJob] Retry #{retry_count}/#{MAX_RETRIES} for user #{user.id}: #{e.message}"
                  sleep(1) # Brief pause before retry
                  retry
                else
                  failed += 1
                  Rails.logger.error "[UpdateUserBatchRecommendationsJob] Failed to generate recommendations for user #{user.id} after #{MAX_RETRIES} retries: #{e.message}\n#{e.backtrace.join("\n")}"
                end
              end
            rescue => e
              failed += 1
              Rails.logger.error "[UpdateUserBatchRecommendationsJob] Failed to process user #{user.id}: #{e.message}\n#{e.backtrace.join("\n")}"
            end
          end
        rescue => e
          # Log batch-level errors
          Rails.logger.error "[UpdateUserBatchRecommendationsJob] Failed to process sub-batch: #{e.message}\n#{e.backtrace.join("\n")}"
          failed += sub_batch_ids.size
        end
        
        sub_batch_duration = Time.current - sub_batch_start
        Rails.logger.info "[UpdateUserBatchRecommendationsJob] Processed sub-batch of #{sub_batch_ids.size} users in #{sub_batch_duration.round(2)}s"
        
        # Force garbage collection between sub-batches to manage memory
        GC.start if rand < 0.3 # Only run GC ~30% of the time to balance performance
        
        # Clear Active Record query cache to prevent memory bloat
        ActiveRecord::Base.connection.clear_query_cache
      end
    end
    
    duration = Time.current - start_time
    Rails.logger.info "[UpdateUserBatchRecommendationsJob] Completed processing recommendations for batch: #{successful} successful, #{failed} failed, #{skipped} skipped in #{duration.round(2)}s"
  end
end 
