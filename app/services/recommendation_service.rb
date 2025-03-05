class RecommendationService
  class << self
    # Generate recommendations for a single user
    def generate_for_user(user)
      Rails.logger.info "[RecommendationService] Generating recommendations for user #{user.id}"
      start_time = Time.current
      
      user_preference = user.ensure_user_preference
      
      # Generate recommendations using the user's preference model
      recommendations = user_preference.generate_recommendations
      
      duration = Time.current - start_time
      Rails.logger.info "[RecommendationService] Generated #{recommendations.size} recommendations for user #{user.id} in #{duration.round(2)}s"
      
      recommendations
    end
    
    # Generate recommendations for all users in batches
    def generate_for_all_users(batch_size: 50)
      Rails.logger.info "[RecommendationService] Starting to generate recommendations for all users"
      start_time = Time.current
      
      total_users = User.count
      processed_users = 0
      successful_users = 0
      failed_users = 0
      
      User.find_in_batches(batch_size: batch_size) do |users_batch|
        batch_start_time = Time.current
        
        users_batch.each do |user|
          begin
            generate_for_user(user)
            successful_users += 1
          rescue => e
            failed_users += 1
            Rails.logger.error "[RecommendationService] Failed to generate recommendations for user #{user.id}: #{e.message}"
          ensure
            processed_users += 1
            
            # Log progress every 10 users or at the end of each batch
            if processed_users % 10 == 0 || processed_users == users_batch.size
              percent_complete = (processed_users.to_f / total_users * 100).round(1)
              Rails.logger.info "[RecommendationService] Progress: #{processed_users}/#{total_users} users (#{percent_complete}%)"
            end
          end
          
          # Force garbage collection periodically to manage memory usage
          GC.start if processed_users % 100 == 0
        end
        
        batch_duration = Time.current - batch_start_time
        Rails.logger.info "[RecommendationService] Processed batch of #{users_batch.size} users in #{batch_duration.round(2)}s"
      end
      
      duration = Time.current - start_time
      Rails.logger.info "[RecommendationService] Completed generating recommendations for all users in #{duration.round(2)}s"
      Rails.logger.info "[RecommendationService] Summary: #{successful_users} successful, #{failed_users} failed, #{processed_users} total"
      
      {
        total_users: processed_users,
        successful_users: successful_users,
        failed_users: failed_users,
        duration: duration.round(2)
      }
    end
  end
end 
