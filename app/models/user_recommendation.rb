# frozen_string_literal: true

# == Schema Information
#
# Table name: user_recommendations
#
#  id                           :bigint           not null, primary key
#  deleted_at                   :datetime
#  processing                   :boolean          default(FALSE)
#  recommendation_reasons       :jsonb
#  recommendation_scores        :jsonb
#  recommendations_generated_at :datetime
#  recommended_content_ids      :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  user_id                      :bigint           not null
#
# Indexes
#
#  index_user_recommendations_on_deleted_at  (deleted_at)
#  index_user_recommendations_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserRecommendation < ApplicationRecord
  acts_as_paranoid
  belongs_to :user, required: true

  def recommendations_outdated?
    Rails.logger.debug "Checking if recommendations are outdated for user #{user_id}"
    Rails.logger.debug "Current recommendation state: content_ids=#{recommended_content_ids.present?}, generated_at=#{recommendations_generated_at}, processing=#{processing?}"
    
    # Don't consider outdated if we're still processing
    return false if processing?
    
    # Check for forced outdated status (set by preferences changes or survey completion)
    if Rails.cache.exist?("force_outdated_recommendations_#{user_id}")
      Rails.logger.info "Recommendations for user #{user_id} are forcibly marked as outdated"
      Rails.cache.delete("force_outdated_recommendations_#{user_id}")
      return true
    end
    
    # Clear the cache if it's stuck
    if Rails.cache.exist?("user_#{user_id}_recommendations_outdated")
      cache_value = Rails.cache.read("user_#{user_id}_recommendations_outdated")
      if cache_value == true && content_ids_present? && !empty_content_ids?
        Rails.logger.info "Clearing stuck cache value for user #{user_id}"
        Rails.cache.delete("user_#{user_id}_recommendations_outdated")
      end
    end
    
    result = Rails.cache.fetch("user_#{user_id}_recommendations_outdated", expires_in: 5.minutes) do
      outdated = false
      reasons = []
      
      # Basic validity checks
      if recommended_content_ids.nil?
        reasons << "content_ids is nil"
        outdated = true
      elsif empty_content_ids?
        reasons << "content_ids is empty" 
        outdated = true
      elsif recommendations_generated_at.nil?
        reasons << "generated_at is nil"
        outdated = true
      # Only check for old recommendations (1 week+)
      elsif (Time.current - recommendations_generated_at) > 7.days
        reasons << "recommendations older than 7 days"
        outdated = true
      end
      
      # Don't check for content updates on normal recommendation views
      # This prevents re-generating recommendations just because content was updated
      
      Rails.logger.debug "Recommendations outdated: #{outdated}#{reasons.present? ? " (#{reasons.join(', ')})" : ''}"
      outdated
    end
    
    Rails.logger.debug "Final outdated status: #{result}"
    result
  end

  # Safe accessors for recommendation content IDs
  def content_ids_present?
    recommended_content_ids.present?
  end

  def empty_content_ids?
    return true if recommended_content_ids.nil?
    
    if recommended_content_ids.is_a?(Hash)
      movie_ids = recommended_content_ids['movies'] || recommended_content_ids[:movies] || []
      show_ids = recommended_content_ids['shows'] || recommended_content_ids[:shows] || []
      movie_ids.empty? && show_ids.empty?
    else
      recommended_content_ids.empty?
    end
  end

  def total_recommendations_count
    return 0 if recommended_content_ids.nil?
    
    if recommended_content_ids.is_a?(Hash)
      movie_count = (recommended_content_ids['movies'] || recommended_content_ids[:movies] || []).size
      show_count = (recommended_content_ids['shows'] || recommended_content_ids[:shows] || []).size
      movie_count + show_count
    else
      recommended_content_ids.size
    end
  end

  def get_all_content_ids
    return [] if recommended_content_ids.nil?
    
    if recommended_content_ids.is_a?(Hash)
      movie_ids = recommended_content_ids['movies'] || recommended_content_ids[:movies] || []
      show_ids = recommended_content_ids['shows'] || recommended_content_ids[:shows] || []
      movie_ids + show_ids
    else
      recommended_content_ids
    end
  end

  def ensure_recommendations
    # If already processing, just return
    if processing?
      Rails.logger.info("Recommendations for user #{user_id} are being processed")
      return false
    end
    
    # Fix recommendations if we have scores but no content IDs
    if recommended_content_ids.nil? && recommendation_scores.present?
      fix_missing_content_ids 
      reload # Make sure we have the latest data
    end
    
    # Check if we have valid recommendations
    has_recommendations = recommended_content_ids.present? && !recommended_content_ids.empty?
    
    # Check if recommendations were generated recently (within the last 5 minutes)
    recently_generated = recommendations_generated_at.present? && 
                        (Time.current - recommendations_generated_at) < 5.minutes
    
    # Log the current state
    Rails.logger.debug "Ensure recommendations for user #{user_id}: " +
                      "has_recommendations=#{has_recommendations}, " +
                      "recently_generated=#{recently_generated}, " +
                      "outdated=#{recommendations_outdated?}"
    
    # If we have recommendations and they're recent, don't regenerate
    if has_recommendations && recently_generated
      Rails.logger.info "Using recently generated recommendations for user #{user_id}"
      return true
    end
    
    # Check if recommendations are outdated and need to be regenerated
    if !has_recommendations || recommendations_outdated?
      Rails.logger.info("Ensuring recommendations for user #{user_id}")
      
      # Start generating recommendations
      update(processing: true)
      
      # Queue the job to generate recommendations
      GenerateRecommendationsJob.perform_later(user_id)
      return false
    end
    
    # We have valid, non-outdated recommendations
    true
  end

  def fix_missing_content_ids
    return unless recommendation_scores.present?
    
    begin
      Rails.logger.info "Fixing missing content IDs for user_recommendation #{id}"
      
      # Extract all content IDs from recommendation_scores
      all_content_ids = recommendation_scores.keys.map(&:to_i).uniq
      
      if all_content_ids.present?
        # Format for SQL array
        content_ids_sql = "ARRAY[#{all_content_ids.join(',')}]::integer[]"
        
        # Update with raw SQL
        sql = <<-SQL
          UPDATE user_recommendations 
          SET recommended_content_ids = #{content_ids_sql}
          WHERE id = #{id};
        SQL
        
        ActiveRecord::Base.connection.execute(sql)
        Rails.logger.info "Fixed missing content IDs for user_recommendation #{id}, set #{all_content_ids.size} content IDs"
      else
        Rails.logger.warn "No content IDs found in recommendation_scores for user_recommendation #{id}"
      end
    rescue => e
      Rails.logger.error "Error fixing missing content IDs: #{e.message}"
    end
  end

  def generate_recommendations
    user_preference = user.user_preference
    
    if user_preference.personality_profiles.blank?
      Rails.logger.error "Cannot generate recommendations: personality_profiles is blank"
      update(processing: false)
      return []
    end
    
    if user_preference.favorite_genres.blank?
      Rails.logger.error "Cannot generate recommendations: favorite_genres is blank"
      update(processing: false)
      return []
    end

    begin
      if user_preference.use_ai
        # Use the AiRecommendationService to generate recommendations directly
        sorted_ids, reasons, scores = AiRecommendationService.generate_recommendations(user_preference)
        
        if sorted_ids.present?
          # Categorize content ids by type
          movie_ids = []
          show_ids = []
          
          Content.where(id: sorted_ids).each do |content|
            if content.content_type == 'movie'
              movie_ids << content.id
            else
              show_ids << content.id
            end
          end
          
          # Update the record with the recommendation data
          update(
            recommended_content_ids: {
              movies: movie_ids,
              shows: show_ids
            },
            recommendation_reasons: reasons,
            recommendation_scores: scores,
            recommendations_generated_at: Time.current,
            processing: false
          )
          
          Rails.logger.info "Saved #{movie_ids.size} movie recommendations and #{show_ids.size} show recommendations"
        else
          Rails.logger.warn "No recommendations generated for user #{user_id}"
          update(processing: false)
        end
        
        # Reload to get the updated content_ids
        reload
        
        Rails.cache.delete_matched("user_#{user_id}_recommendations_*")
        Rails.cache.delete("user_#{user_id}_recommendations_page_1")
        
        # Return the content IDs
        get_all_content_ids
      else
        recommended_ids = generate_internal_recommendations(user_preference)
        update(
          recommended_content_ids: {
            movies: recommended_ids,
            shows: []
          },
          recommendation_reasons: {},
          recommendation_scores: {},
          recommendations_generated_at: Time.current,
          processing: false
        )
        
        Rails.cache.delete_matched("user_#{user_id}_recommendations_*")
        Rails.cache.delete("user_#{user_id}_recommendations_page_1")
        
        recommended_ids
      end
    rescue StandardError => e
      update(processing: false)
      Rails.logger.error "Failed to generate recommendations: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      []
    end
  end

  def calculate_match_score(genre_ids, user_preference)
    user_preference.calculate_match_score(genre_ids)
  end

  # Call this method when preferences are updated or surveys are completed
  def mark_as_outdated!
    Rails.logger.info "Marking recommendations as outdated for user_recommendation #{id}"
    
    begin
      # Use raw SQL to clear fields with proper types
      sql = <<-SQL
        UPDATE user_recommendations 
        SET recommended_content_ids = NULL,
            recommendation_reasons = NULL::jsonb, 
            recommendation_scores = NULL::jsonb,
            recommendations_generated_at = NULL,
            processing = FALSE
        WHERE id = #{id};
      SQL
      
      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "Successfully marked recommendations as outdated for user_recommendation #{id}"
    rescue => e
      Rails.logger.error "Error marking recommendations as outdated: #{e.message}"
      # Fallback to simpler update if needed
      update_columns(
        recommendations_generated_at: nil,
        processing: false
      )
    end
  end

  private

  def generate_internal_recommendations(user_preference)
    base_content = Content.all
    base_content = base_content.where(adult: [false, nil]) if user_preference.disable_adult_content

    content_with_scores = base_content.map do |content|
      {
        id: content.id,
        match_score: user_preference.calculate_match_score(content.genre_ids_array)
      }
    end

    content_with_scores.sort_by { |r| -r[:match_score] }
                       .first(100)
                       .map { |r| r[:id] }
  end
  
  # Add ransackable definitions
  def self.ransackable_attributes(auth_object = nil)
    [
      "id", "user_id", "processing", "recommendations_generated_at", 
      "created_at", "updated_at", "deleted_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
end
