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
#  processing                   :boolean          default(FALSE)
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

  validates :ai_model, inclusion: { 
    in: AiModelsConfig::MODELS.keys,
    allow_nil: true 
  }

  def generate_recommendations
    return [] if personality_profiles.blank? || favorite_genres.blank?

    begin
      if use_ai
        recommended_ids, reasons, match_scores = AiRecommendationService.generate_recommendations(self)
        update(
          recommended_content_ids: recommended_ids,
          recommendation_reasons: reasons,
          recommendation_scores: match_scores,
          recommendations_generated_at: Time.current,
          processing: false
        )
      else
        recommended_ids = generate_internal_recommendations
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

  def calculate_match_score(genre_ids)
    genre_names = Genre.where(tmdb_id: genre_ids).pluck(:name)
    big_five_score = calculate_big_five_score(genre_names)
    favorite_genres_score = calculate_favorite_genres_score(genre_names)
    (big_five_score * 0.7) + (favorite_genres_score * 0.3)
  end

  def personality_profiles
    profiles = read_attribute(:personality_profiles)
    return {} if profiles.nil?
    
    # Handle string representation (which might happen with some ActiveRecord operations)
    profiles = JSON.parse(profiles) if profiles.is_a?(String)
    
    # Ensure we return a hash with symbolized keys
    profiles.is_a?(Hash) ? profiles.deep_symbolize_keys : {}
  end

  def favorite_genres
    read_attribute(:favorite_genres) || []
  end

  def self.ransackable_attributes(auth_object = nil)
    [
      "id", 
      "user_id", 
      "favorite_genres", 
      "personality_profiles", 
      "recommended_content_ids",
      "recommendations_generated_at",
      "disable_adult_content",
      "use_ai",
      "ai_model",
      "created_at", 
      "updated_at"
    ]
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

  def ai_model
    read_attribute(:ai_model) || AiModelsConfig.default_model
  end

  private

  def calculate_big_five_score(genres)
    score = 0
    profiles = personality_profiles
    
    # Extract big_five from the profile structure
    big_five = if profiles.is_a?(Hash)
      if profiles.key?(:big_five)
        profiles[:big_five]
      elsif profiles.key?('big_five')
        profiles['big_five']
      else
        profiles
      end
    else
      {}
    end
    
    Rails.logger.info("Calculating big five score with profiles: #{big_five.inspect}")
    Rails.logger.info("Genres: #{genres.inspect}")
    
    GENRE_MAPPING.each do |trait, trait_genres|
      trait_str = trait.to_s
      trait_sym = trait.to_sym
      
      # Try both symbol and string keys
      trait_score = big_five[trait_sym].to_f
      trait_score = big_five[trait_str].to_f if trait_score == 0 && big_five.key?(trait_str)
      
      match = (genres & trait_genres).size
      
      Rails.logger.info("Trait: #{trait_str}, Score: #{trait_score}, Matching genres: #{match}")
      
      score += trait_score * match
    end
    
    Rails.logger.info("Final big five score: #{score}")
    score
  end

  def calculate_favorite_genres_score(genres)
    user_favorite_genres = favorite_genres.is_a?(String) ? favorite_genres.split(',').map(&:strip) : favorite_genres
    
    Rails.logger.info("Calculating favorite genres score")
    Rails.logger.info("User favorite genres: #{user_favorite_genres.inspect}")
    Rails.logger.info("Content genres: #{genres.inspect}")
    
    if user_favorite_genres.empty?
      Rails.logger.warn("User has no favorite genres")
      return 0
    end
    
    matching_genres = genres & user_favorite_genres
    score = matching_genres.size.to_f / user_favorite_genres.size
    
    Rails.logger.info("Matching genres: #{matching_genres.inspect}")
    Rails.logger.info("Score: #{score}")
    
    score
  end

  def generate_internal_recommendations
    base_content = Content.all
    base_content = base_content.where(adult: [false, nil]) if disable_adult_content

    content_with_scores = base_content.map do |content|
      {
        id: content.id,
        match_score: calculate_match_score(content.genre_ids_array)
      }
    end

    content_with_scores.sort_by { |r| -r[:match_score] }
                       .first(100)
                       .map { |r| r[:id] }
  end

  def generate_internal_recommendations
    base_content = Content.all
    base_content = base_content.where(adult: [false, nil]) if disable_adult_content

    content_with_scores = base_content.map do |content|
      {
        id: content.id,
        match_score: calculate_match_score(content.genre_ids_array)
      }
    end

    content_with_scores.sort_by { |r| -r[:match_score] }
                       .first(100)
                       .map { |r| r[:id] }
  end
end
