class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = User.find(params[:id])
  end

  def profile
    @user = current_user
    @user_preference = current_user.user_preference || current_user.build_user_preference
    genres = TmdbService.fetch_genres
    @genres = genres[:user_facing_genres]
    @all_genres = genres[:all_genres]
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(user_params)
      redirect_to profile_user_path(@user), notice: "Profile was successfully updated."
    else
      render :edit
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :gender, :dob, :email)
  end
end
