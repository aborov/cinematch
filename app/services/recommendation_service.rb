class RecommendationService
  class << self
    # Generate recommendations for a single user
    def generate_for_user(user)
      Rails.logger.info "[RecommendationService] Generating recommendations for user #{user.id}"
      start_time = Time.current
      
      user_preference = user.ensure_user_preference
      
      # Skip if user has no preferences
      if user_preference.personality_profiles.blank? || user_preference.favorite_genres.blank?
        Rails.logger.info "[RecommendationService] Skipping user #{user.id} - missing preferences"
        return []
      end
      
      # Generate recommendations using the user's preference model
      recommendations = generate_recommendations_for_preference(user_preference)
      
      duration = Time.current - start_time
      Rails.logger.info "[RecommendationService] Generated #{recommendations.size} recommendations for user #{user.id} in #{duration.round(2)}s"
      
      recommendations
    end
    
    # Generate recommendations for a user preference
    def generate_recommendations_for_preference(user_preference)
      # Preload all genres to avoid N+1 queries
      all_genres = Genre.all.index_by(&:tmdb_id)
      
      # Get base content query
      base_content = Content.all
      base_content = base_content.where(adult: [false, nil]) if user_preference.disable_adult_content
      
      # Preload genre_ids_array for all content to avoid N+1 queries
      # Use select instead of pluck to keep the Content objects
      content_with_genres = base_content.select(:id, :genre_ids)
      
      # Calculate match scores in memory to reduce database load
      content_with_scores = content_with_genres.map do |content|
        {
          id: content.id,
          match_score: calculate_match_score(content.genre_ids_array, user_preference, all_genres)
        }
      end
      
      # Sort and get top recommendations
      sorted_recommendations = content_with_scores.sort_by { |r| -r[:match_score] }
      top_recommendations = sorted_recommendations.first(100).map { |r| r[:id] }
      
      # Update user preference with new recommendations
      user_preference.update(
        recommended_content_ids: top_recommendations, 
        recommendations_generated_at: Time.current
      )
      
      # Clear cache
      Rails.cache.delete_matched("user_#{user_preference.user_id}_recommendations_*")
      Rails.cache.delete("user_#{user_preference.user_id}_recommendations_page_1")
      
      top_recommendations
    end
    
    # Generate recommendations for all users in batches
    def generate_for_all_users(batch_size: 50)
      Rails.logger.info "[RecommendationService] Starting to generate recommendations for all users"
      start_time = Time.current
      
      total_users = User.count
      processed_users = 0
      successful_users = 0
      failed_users = 0
      
      # Preload all genres to avoid N+1 queries
      all_genres = Genre.all.index_by(&:tmdb_id)
      
      User.find_in_batches(batch_size: batch_size) do |users_batch|
        batch_start_time = Time.current
        
        # Preload user preferences for the batch
        user_ids = users_batch.map(&:id)
        user_preferences = UserPreference.where(user_id: user_ids).index_by(&:user_id)
        
        users_batch.each do |user|
          begin
            # Get or create user preference
            user_preference = user_preferences[user.id] || user.ensure_user_preference
            
            # Skip if user has no preferences
            if user_preference.personality_profiles.blank? || user_preference.favorite_genres.blank?
              Rails.logger.info "[RecommendationService] Skipping user #{user.id} - missing preferences"
              processed_users += 1
              next
            end
            
            # Generate recommendations
            generate_recommendations_for_preference(user_preference)
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
        end
        
        batch_duration = Time.current - batch_start_time
        Rails.logger.info "[RecommendationService] Processed batch of #{users_batch.size} users in #{batch_duration.round(2)}s"
        
        # Force garbage collection between batches to manage memory usage
        GC.start
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
    
    private
    
    # Calculate match score for content based on genres
    def calculate_match_score(genre_ids, user_preference, all_genres)
      # Get genre names from preloaded genres
      genre_names = genre_ids.map { |id| all_genres[id]&.name }.compact
      
      # Calculate scores
      big_five_score = calculate_big_five_score(genre_names, user_preference.personality_profiles)
      favorite_genres_score = calculate_favorite_genres_score(genre_names, user_preference.favorite_genres)
      
      # Weighted score
      (big_five_score * 0.7) + (favorite_genres_score * 0.3)
    end
    
    # Calculate big five personality score
    def calculate_big_five_score(genres, personality_profiles)
      score = 0
      UserPreference::GENRE_MAPPING.each do |trait, trait_genres|
        match = (genres & trait_genres).size
        score += personality_profiles[trait.to_s].to_f * match
      end
      score
    end
    
    # Calculate favorite genres score
    def calculate_favorite_genres_score(genres, favorite_genres)
      user_favorite_genres = favorite_genres.is_a?(String) ? favorite_genres.split(',').map(&:strip) : favorite_genres
      return 0 if user_favorite_genres.empty?
      
      matching_genres = genres & user_favorite_genres
      matching_genres.size.to_f / user_favorite_genres.size
    end
  end
end 
