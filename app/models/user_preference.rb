# frozen_string_literal: true

# == Schema Information
#
# Table name: user_preferences
#
#  id                           :bigint           not null, primary key
#  deleted_at                   :datetime
#  disable_adult_content        :boolean
#  favorite_genres              :json
#  personality_profiles         :json
#  recommendations_generated_at :datetime
#  recommended_content_ids      :integer          default([]), is an Array
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
    return [] if personality_profiles.blank? || favorite_genres.blank?

    base_content = Content.all
    base_content = base_content.where(adult: [false, nil]) if disable_adult_content

    content_with_scores = base_content.map do |content|
      {
        id: content.id,
        match_score: calculate_match_score(content.genre_ids_array)
      }
    end

    sorted_recommendations = content_with_scores.sort_by { |r| -r[:match_score] }
    top_recommendations = sorted_recommendations.first(100).map { |r| r[:id] }

    update(recommended_content_ids: top_recommendations, recommendations_generated_at: Time.current)
    Rails.cache.delete_matched("user_#{user_id}_recommendations_*")
    Rails.cache.delete("user_#{user_id}_recommendations_page_1")
    top_recommendations
  end

  def calculate_match_score(genre_ids)
    genre_names = Genre.where(tmdb_id: genre_ids).pluck(:name)
    big_five_score = calculate_big_five_score(genre_names)
    favorite_genres_score = calculate_favorite_genres_score(genre_names)
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
    user_favorite_genres = favorite_genres.is_a?(String) ? favorite_genres.split(',').map(&:strip) : favorite_genres

    matching_genres = genres & user_favorite_genres
    matching_genres.size.to_f / user_favorite_genres.size
  end
end
