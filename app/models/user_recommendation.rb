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
      end
      return false
    end
    
    # We have valid, non-outdated recommendations
    true
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
        recommended_ids, reasons, match_scores = AiRecommendationService.generate_recommendations(user_preference)
        update(
          recommended_content_ids: recommended_ids,
          recommendation_reasons: reasons,
          recommendation_scores: match_scores,
          recommendations_generated_at: Time.current,
          processing: false
        )
      else
        recommended_ids = generate_internal_recommendations(user_preference)
        update(
          recommended_content_ids: recommended_ids,
          recommendation_reasons: {},
          recommendation_scores: {},
          recommendations_generated_at: Time.current,
          processing: false
        )
      end
      
      Rails.cache.delete_matched("user_#{user_id}_recommendations_*")
      Rails.cache.delete("user_#{user_id}_recommendations_page_1")
      
      recommended_ids
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
end
