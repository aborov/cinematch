class UsersController < ApplicationController
  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: "Profile was successfully updated."
    else
      render :edit
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :gender, :dob, :email)
  end
end
