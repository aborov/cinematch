# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, except: [:restore_account_form, :restore]
  skip_before_action :verify_authenticity_token, only: [:restore]
  skip_after_action :verify_authorized, only: [:restore_account_form, :restore]
  
  def show
    @user = current_user
    authorize @user
    @user_preference = @user.user_preference || @user.build_user_preference
    @genres = TmdbService.fetch_genres[:user_facing_genres]
    @available_models = AiModelsConfig.available_models
    
    # Generate personality profile regardless of survey status
    # This ensures the profile is displayed even if the survey was just completed
    @personality_profile = PersonalityProfileService.generate_profile(@user, true)
    
    # Ensure the user has a personality summary if they've completed at least the basic survey
    if @user.basic_survey_completed? && @user.user_preference.personality_summary.blank?
      @user.user_preference.personality_summary = PersonalitySummaryService.generate_summary(@user)
      @user.user_preference.save
    end
    
    # Log status for debugging
    Rails.logger.info "User #{@user.id} Profile View"
    Rails.logger.info "Basic Survey Completed: #{@user.basic_survey_completed?}"
    Rails.logger.info "Extended Survey Completed: #{@user.extended_survey_completed?}"
    Rails.logger.info "Extended Survey In Progress: #{@user.extended_survey_in_progress?}"
    Rails.logger.info "Personality Profile Generated: #{@personality_profile.present?}"
    Rails.logger.info "Big Five Present: #{@personality_profile[:big_five].present?}" if @personality_profile.present?
    
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
