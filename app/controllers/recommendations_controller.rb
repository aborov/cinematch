class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_user_preferences, only: [:index]

  def index
    # @recommendations = generate_recommendations(current_user)
    @user_preference = current_user.user_preference
  end

  private

  def generate_recommendations(user)
    preferences = user.user_preference
    # Logic to generate recommendations based on preferences
    # Example:
    # Content.where(genre: preferences.favorite_genres).limit(10)
  end

  def check_user_preferences
    unless current_user.user_preference.present?
      redirect_to survey_responses_path, alert: 'Please complete the survey to receive recommendations.'
    end
  end
end
