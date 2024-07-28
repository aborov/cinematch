class UserPreferencesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user_preference = current_user.user_preference
    genres = TmdbService.fetch_genres
    @genres = genres[:user_facing_genres]
    @all_genres = genres[:all_genres]
  end

  def update
    @user_preference = current_user.user_preference || current_user.build_user_preference
    genres = user_preference_params[:favorite_genres].reject(&:blank?)
    if @user_preference.update(favorite_genres: genres)
      redirect_to recommendations_path, notice: 'Preferences updated successfully.'
    else
      render :edit
    end
  end

  private

  def user_preference_params
    params.require(:user_preference).permit(favorite_genres: [])
  end
end
