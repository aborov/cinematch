# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, except: [:restore_account_form, :restore]
  skip_before_action :verify_authenticity_token, only: [:restore]
  skip_after_action :verify_authorized, only: [:restore_account_form, :restore]
  
  def show
    @user = current_user
    authorize @user
    @user_preference = @user.user_preference || @user.build_user_preference
    @genres = Genre.all
    render :show
  end

  def edit
    @user = current_user
    authorize @user
  end

  def update
    @user = current_user
    authorize @user
    if @user.update(user_params)
      redirect_to profile_path, notice: 'Profile was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    authorize @user
    if @user == current_user
      @user.destroy
      sign_out @user
      redirect_to new_user_session_path, notice: 'Your account has been successfully deleted. You can restore it within 30 days by clicking "Restore" on the sign-up page.'
    else
      redirect_to edit_user_registration_path, alert: 'Failed to delete account. Please try again or contact support.'
    end
  end

  def restore_account_form
    render 'restore_account'
  end

  def restore
    @user = User.only_deleted.find_by(email: params[:email])
    if @user
      begin
        ActiveRecord::Base.transaction do
          @user.restore!
          UserPreference.only_deleted.where(user_id: @user.id).each(&:restore!)
          SurveyResponse.only_deleted.where(user_id: @user.id).each(&:restore!)
        end
        flash[:notice] = 'Your account has been successfully restored. Please sign in.'
        redirect_to new_user_session_path
      rescue => e
        Rails.logger.error "Failed to restore user account: #{e.message}"
        flash[:alert] = 'Unable to restore account. Please contact support.'
        redirect_to new_user_registration_path
      end
    else
      flash[:alert] = 'No deleted account found with this email address.'
      redirect_to new_user_registration_path
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :gender, :dob)
  end
end
