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
      # Check if we have cached genre data
      begin
        all_genres = Rails.cache.fetch("all_genres", expires_in: 24.hours) do
          Genre.all.index_by(&:tmdb_id)
        end
      rescue => e
        Rails.logger.error "[RecommendationService] Cache error fetching genres: #{e.message}"
        all_genres = Genre.all.index_by(&:tmdb_id)
      end
      
      # Get base content query
      base_content = Content.all
      base_content = base_content.where(adult: [false, nil]) if user_preference.disable_adult_content
      
      # Use cache for content with genres to avoid repeated database queries
      begin
        content_with_genres = Rails.cache.fetch("content_with_genres", expires_in: 6.hours) do
          base_content.select(:id, :genre_ids).map do |content|
            {
              id: content.id,
              genre_ids: content.genre_ids_array
            }
          end
        end
      rescue => e
        Rails.logger.error "[RecommendationService] Cache error fetching content: #{e.message}"
        content_with_genres = base_content.select(:id, :genre_ids).map do |content|
          {
            id: content.id,
            genre_ids: content.genre_ids_array
          }
        end
      end
      
      # Calculate match scores in memory to reduce database load
      content_with_scores = []
      
      # Process in smaller batches to reduce memory pressure
      content_with_genres.each_slice(500) do |batch|
        batch_scores = batch.map do |content|
          begin
            {
              id: content[:id],
              match_score: calculate_match_score(content[:genre_ids], user_preference, all_genres)
            }
          rescue => e
            Rails.logger.error "[RecommendationService] Error calculating match score for content #{content[:id]}: #{e.message}"
            {
              id: content[:id],
              match_score: 0 # Default to zero match score on error
            }
          end
        end
        content_with_scores.concat(batch_scores)
        
        # Allow GC to run between batches
        GC.start if rand < 0.2 # Only run GC ~20% of the time
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
      begin
        Rails.cache.delete_matched("user_#{user_preference.user_id}_recommendations_*")
        Rails.cache.delete("user_#{user_preference.user_id}_recommendations_page_1")
      rescue => e
        Rails.logger.error "[RecommendationService] Cache error clearing recommendations: #{e.message}"
      end
      
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
      begin
        all_genres = Rails.cache.fetch("all_genres", expires_in: 24.hours) do
          Genre.all.index_by(&:tmdb_id)
        end
      rescue => e
        Rails.logger.error "[RecommendationService] Cache error fetching genres: #{e.message}"
        all_genres = Genre.all.index_by(&:tmdb_id)
      end
      
      # Cache content with genres for the duration of this job
      content_with_genres = nil
      
      User.find_in_batches(batch_size: batch_size) do |users_batch|
        batch_start_time = Time.current
        
        # Preload user preferences for the batch
        user_ids = users_batch.map(&:id)
        user_preferences = UserPreference.where(user_id: user_ids).index_by(&:user_id)
        
        # Lazy load content with genres only when needed
        if content_with_genres.nil?
          begin
            content_with_genres = Rails.cache.fetch("content_with_genres", expires_in: 6.hours) do
              Content.select(:id, :genre_ids).map do |content|
                {
                  id: content.id,
                  genre_ids: content.genre_ids_array
                }
              end
            end
          rescue => e
            Rails.logger.error "[RecommendationService] Cache error fetching content: #{e.message}"
            content_with_genres = Content.select(:id, :genre_ids).map do |content|
              {
                id: content.id,
                genre_ids: content.genre_ids_array
              }
            end
          end
        end
        
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
            content_with_scores = []
            
            # Process in smaller batches to reduce memory pressure
            content_with_genres.each_slice(500) do |batch|
              batch_scores = batch.map do |content|
                {
                  id: content[:id],
                  match_score: calculate_match_score(content[:genre_ids], user_preference, all_genres)
                }
              end
              content_with_scores.concat(batch_scores)
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
            begin
              Rails.cache.delete_matched("user_#{user_preference.user_id}_recommendations_*")
              Rails.cache.delete("user_#{user_preference.user_id}_recommendations_page_1")
            rescue => e
              Rails.logger.error "[RecommendationService] Cache error clearing recommendations: #{e.message}"
            end
            
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
      # Log problematic genre_ids for debugging
      if !genre_ids.is_a?(Array)
        Rails.logger.warn "[RecommendationService] Non-array genre_ids detected: #{genre_ids.inspect} (#{genre_ids.class})"
      end
      
      # Ensure genre_ids is an array
      genre_ids = [genre_ids] unless genre_ids.is_a?(Array)
      
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
        # Skip if the user doesn't have this trait
        next unless personality_profiles[trait].present?
        
        # Calculate the match for this trait
        trait_score = personality_profiles[trait].to_f / 100
        matching_genres = genres.count { |g| trait_genres.include?(g) }
        
        # Add to the total score
        score += (matching_genres * trait_score)
      end
      
      score
    end
    
    # Calculate favorite genres score
    def calculate_favorite_genres_score(genres, favorite_genres)
      return 0 if favorite_genres.blank?
      
      # Count how many of the content's genres match the user's favorites
      matching_genres = genres.count { |g| favorite_genres.include?(g) }
      
      # Normalize by the number of genres in the content
      genres.empty? ? 0 : (matching_genres.to_f / genres.size)
    end
  end
end 
