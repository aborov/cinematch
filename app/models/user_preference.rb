# frozen_string_literal: true

# == Schema Information
#
# Table name: user_preferences
#
#  id                           :bigint           not null, primary key
#  ai_model                     :string
#  deleted_at                   :datetime
#  disable_adult_content        :boolean
#  favorite_genres              :json
#  personality_profiles         :json
#  recommendation_reasons       :jsonb
#  recommendation_scores        :jsonb
#  recommendations_generated_at :datetime
#  recommended_content_ids      :integer          default([]), is an Array
#  use_ai                       :boolean          default(FALSE)
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  user_id                      :bigint           not null
#
# Indexes
#
#  index_user_preferences_on_deleted_at  (deleted_at)
#  index_user_preferences_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserPreference < ApplicationRecord
  acts_as_paranoid
  belongs_to :user, required: true

  GENRE_MAPPING = {
    openness: %w[Science-Fiction Fantasy Animation],
    conscientiousness: %w[Drama Biography History],
    extraversion: %w[Comedy Action Adventure],
    agreeableness: %w[Romance Family Music],
    neuroticism: %w[Thriller Mystery Horror]
  }.freeze

  def generate_recommendations
    # Check if we have the necessary data
    if personality_profiles.blank? || favorite_genres.blank?
      Rails.logger.warn "[UserPreference] Cannot generate recommendations: missing personality_profiles or favorite_genres for user #{user_id}"
      return []
    end

    # Start with all content
    base_content = Content.all
    
    # Filter out adult content if needed
    base_content = base_content.where(adult: [false, nil]) if disable_adult_content

    # Calculate match scores for each content item
    begin
      content_with_scores = base_content.map do |content|
        {
          id: content.id,
          match_score: calculate_match_score(content.genre_ids_array)
        }
      end

      # Sort by match score (descending)
      sorted_recommendations = content_with_scores.sort_by { |r| -r[:match_score] }
      
      # Take top 100 recommendations
      top_recommendations = sorted_recommendations.first(100).map { |r| r[:id] }

      # Update user preferences with new recommendations
      update(
        recommended_content_ids: top_recommendations, 
        recommendations_generated_at: Time.current
      )
      
      # Clear cache
      Rails.cache.delete_matched("user_#{user_id}_recommendations_*")
      Rails.cache.delete("user_#{user_id}_recommendations_page_1")
      
      # Return the recommendations
      top_recommendations
    rescue => e
      Rails.logger.error "[UserPreference] Error generating recommendations for user #{user_id}: #{e.message}\n#{e.backtrace.join("\n")}"
      []
    end
  end

  def calculate_match_score(genre_ids)
    # Ensure genre_ids is an array of integers
    genre_ids = if genre_ids.nil?
                  []
                elsif !genre_ids.is_a?(Array)
                  # Only log a warning for unexpected types, not for single integers
                  unless genre_ids.is_a?(Integer) || genre_ids.is_a?(String)
                    Rails.logger.warn "[UserPreference] Non-array genre_ids detected: #{genre_ids.inspect} (#{genre_ids.class})"
                  end
                  Array(genre_ids).map(&:to_i)
                else
                  genre_ids.map(&:to_i)
                end
                
    # Get genre names for the IDs
    genre_names = Genre.where(tmdb_id: genre_ids).pluck(:name)
    
    # Calculate scores
    big_five_score = calculate_big_five_score(genre_names)
    favorite_genres_score = calculate_favorite_genres_score(genre_names)
    
    # Weighted combination of scores
    (big_five_score * 0.7) + (favorite_genres_score * 0.3)
  end

  def personality_profiles
    read_attribute(:personality_profiles) || {}
  end

  def favorite_genres
    read_attribute(:favorite_genres) || []
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "favorite_genres", "id", "personality_profiles", "updated_at", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
  
  def recommendations_outdated?
    Rails.cache.fetch("user_#{user_id}_recommendations_outdated", expires_in: 5.minutes) do
      recommended_content_ids.empty? ||
        recommendations_generated_at.nil? ||
        updated_at > recommendations_generated_at ||
        Content.where("updated_at > ?", recommendations_generated_at).exists?
    end
  end

  private

  def calculate_big_five_score(genres)
    score = 0
    GENRE_MAPPING.each do |trait, trait_genres|
      match = (genres & trait_genres).size
      score += personality_profiles[trait.to_s].to_f * match
    end
    score
  end

  def calculate_favorite_genres_score(genres)
    # Ensure user_favorite_genres is an array of strings
    user_favorite_genres = case favorite_genres
                           when String
                             favorite_genres.split(',').map(&:strip)
                           when Array
                             favorite_genres
                           else
                             []
                           end

    # Avoid division by zero
    return 0.0 if user_favorite_genres.empty?

    # Find matching genres
    matching_genres = genres & user_favorite_genres
    
    # Calculate score as proportion of matching genres
    matching_genres.size.to_f / user_favorite_genres.size
  end
end
