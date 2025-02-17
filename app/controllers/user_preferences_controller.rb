# frozen_string_literal: true

class UserPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_preference
  after_action :verify_authorized

  def edit
    authorize @user_preference
    genres = TmdbService.fetch_genres
    @genres = genres[:user_facing_genres]
    @all_genres = genres[:all_genres]
  end

  def update
    authorize @user_preference
    genres = process_genre_preferences(user_preference_params[:favorite_genres])
    
    update_params = {
      favorite_genres: genres,
      disable_adult_content: user_preference_params[:disable_adult_content] == '1',
      use_ai: user_preference_params[:use_ai] == '1'
    }

    if @user_preference.update(update_params)
      Rails.logger.info "User preference updated: #{@user_preference.attributes}"
      new_recommendations = @user_preference.generate_recommendations
      if new_recommendations.present?
        redirect_to recommendations_path, notice: 'Preferences updated successfully. Your recommendations have been updated.'
      else
        redirect_to recommendations_path, alert: 'Preferences updated, but we couldn\'t generate new recommendations. Please try again later.'
      end
    else
      Rails.logger.error "Failed to update user preference: #{@user_preference.errors.full_messages}"
      @genres = TmdbService.fetch_genres[:user_facing_genres]
      render :edit
    end
  end

  def create
    @user_preference = current_user.ensure_user_preference
    @user_preference.recommendations_generated_at = Time.current if @user_preference.new_record?

    if @user_preference.update(survey_params)
      recommendations = @user_preference.generate_recommendations
      if recommendations.present?
        redirect_to recommendations_path, notice: 'Survey completed. Here are your personalized recommendations!'
      else
        redirect_to recommendations_path, alert: 'Survey completed, but we couldn\'t generate recommendations. Please try again later.'
      end
    else
      render :index
    end
  end

  private

  def set_user_preference
    @user_preference = current_user.user_preference || current_user.build_user_preference
    authorize @user_preference, :manage?
  end

  def user_preference_params
    params.require(:user_preference).permit(:use_ai, :disable_adult_content, favorite_genres: [])
  end

  def process_genre_preferences(genres)
    return [] if genres.blank?

    genres.reject(&:blank?).map do |genre|
      case genre
      when 'Sci-Fi & Fantasy'
        ['Science Fiction', 'Fantasy']
      when 'Action & Adventure'
        ['Action', 'Adventure']
      when 'War & Politics'
        ['War', 'Politics']
      else
        genre
      end
    end.flatten.uniq
  end
end
