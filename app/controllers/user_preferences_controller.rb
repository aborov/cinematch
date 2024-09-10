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
    genres = user_preference_params[:favorite_genres].reject(&:blank?)
    disable_adult_content = user_preference_params[:disable_adult_content] == '1' # Convert to boolean

    if @user_preference.update(favorite_genres: genres, disable_adult_content: disable_adult_content)
      redirect_to recommendations_path, notice: 'Preferences updated successfully.'
    else
      render :edit
    end
  end

  private

  def set_user_preference
    @user_preference = current_user.user_preference || current_user.build_user_preference
    authorize @user_preference, :manage?
  end

  def user_preference_params
    params.require(:user_preference).permit(:disable_adult_content, favorite_genres: [])
  end
end
