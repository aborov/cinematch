class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:show, :edit, :update, :profile]

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to profile_user_path(@user), notice: "Profile was successfully updated."
    else
      render :edit
    end
  end

  def profile
    @user_preference = current_user.user_preference || current_user.build_user_preference
    @genres = Genre.select(:name).distinct
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :gender, :dob, :email)
  end
end
