class UserPreferencesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user_preference = current_user.user_preference
    @genres = ["Action", "Adventure", "Comedy", "Crime", "Drama", "Fantasy", "Historical", "Horror", "Romance", "Sci-Fi", "Thriller", "Western", "Other"]
  end

  def update
    @user_preference = current_user.user_preference

    if @user_preference.update(user_preference_params)
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
