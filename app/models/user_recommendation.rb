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
#  recommended_content_ids      :integer          default([]), is an Array
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
    Rails.cache.fetch("user_#{user_id}_recommendations_outdated", expires_in: 5.minutes) do
      recommended_content_ids.empty? ||
        recommendations_generated_at.nil? ||
        updated_at > recommendations_generated_at ||
        Content.where("updated_at > ?", recommendations_generated_at).exists?
    end
  end

  def ensure_recommendations
    if recommendations_outdated? || recommended_content_ids.blank?
      Rails.logger.info("Ensuring recommendations for user #{user_id}")
      # Avoid queueing multiple jobs by checking if already processing
      unless processing?
        update(processing: true)
        GenerateRecommendationsJob.perform_later(user_id)
      end
      return false
    end
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
