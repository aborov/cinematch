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
    @available_models = AiModelsConfig.available_models
  end

  def update
    authorize @user_preference
    genres = process_genre_preferences(user_preference_params[:favorite_genres])
    
    update_params = {
      favorite_genres: genres,
      disable_adult_content: user_preference_params[:disable_adult_content] == '1',
      use_ai: user_preference_params[:use_ai] == '1',
      ai_model: user_preference_params[:ai_model]
    }

    if @user_preference.update(update_params)
      # Log the successful update
      Rails.logger.info "User preference updated: #{@user_preference.attributes.inspect}"
      
      # Clear any user recommendation cache
      Rails.cache.delete_matched("user_#{current_user.id}_recommendations_*")
      
      # Trigger recommendation generation in background
      if params[:generate_recommendations]
        user_recommendation = current_user.user_recommendation || current_user.build_user_recommendation
        # Mark recommendations as outdated first
        user_recommendation.mark_as_outdated!
        user_recommendation.update(processing: true)
        GenerateRecommendationsJob.perform_later(current_user.id)
        redirect_to recommendations_path, notice: 'Preferences updated. Your recommendations are being generated...'
      else
        # Just mark as outdated, but don't generate yet - will happen when user visits recommendations
        user_recommendation = current_user.user_recommendation || current_user.build_user_recommendation
        user_recommendation.mark_as_outdated!
        redirect_to profile_path, notice: 'Preferences updated successfully.'
      end
    else
      @genres = Genre.user_facing_genres
      @available_models = AiModelsConfig.available_models
      render :edit
    end
  end

  def create
    @user_preference = current_user.ensure_user_preference

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
    params.require(:user_preference).permit(:disable_adult_content, :use_ai, :ai_model, favorite_genres: [])
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
