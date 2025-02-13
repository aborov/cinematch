# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_preference
  before_action :set_survey_type

  def index
    @survey_type = params[:type] || 'basic'
    @questions = SurveyQuestion.where(survey_type: @survey_type)
                              .order(Arel.sql('CASE 
                                      WHEN question_type = \'attention_check\' THEN 1 
                                      ELSE 0 
                                    END, RANDOM()')).to_a

    if @questions.empty?
      flash[:alert] = "No questions found for this survey type. Please run rails db:seed to populate questions."
      redirect_to root_path and return
    end

    @total_questions = @questions.length
    @genres = TmdbService.fetch_genres[:user_facing_genres]
    @progress = calculate_survey_progress
    
    # Set the session variable after showing the welcome modal
    session[:welcome_modal_shown] = true if show_welcome_modal?
    
    authorize :survey, :index?
  end

  def create
    @user_preference = current_user.ensure_user_preference
    authorize :survey, :create?
    
    if process_survey_responses
      handle_successful_submission
    else
      handle_failed_submission
    end
  end

  def save_progress
    responses = survey_params[:personality_responses]&.to_h || {}
    current_user.survey_responses.transaction do
      responses.each do |question_id, response|
        current_user.survey_responses.find_or_initialize_by(
          survey_question_id: question_id
        ).update!(response: response)
      end
    end
    
    render json: { status: 'success' }
  rescue => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_entity
  end

  private

  def set_survey_type
    @survey_type = params[:type] == 'extended' ? 'extended' : 'basic'
  end

  def calculate_survey_progress
    completed = current_user.survey_responses.count
    total = SurveyQuestion.where(survey_type: @survey_type).count
    (completed.to_f / total * 100).round
  end

  def process_survey_responses
    personality_responses = survey_params[:personality_responses]&.to_h || {}
    favorite_genres = survey_params[:favorite_genres] || []
    
    survey_response_controller = SurveyResponsesController.new
    if survey_response_controller.process_responses(current_user, personality_responses)
      @user_preference.update(favorite_genres: favorite_genres)
      true
    else
      false
    end
  end

  def handle_successful_submission
    GenerateRecommendationsJob.perform_later(@user_preference.id)
    
    if @survey_type == 'basic'
      redirect_to recommendations_path, 
                  notice: 'Basic survey completed! Check your profile for insights or continue with the extended survey for deeper personalization.'
    else
      redirect_to recommendations_path, 
                  notice: 'Extended survey completed! Visit your profile to see your detailed psychological insights.'
    end
  end

  def ensure_user_preference
    @user_preference = current_user.ensure_user_preference
  end

  def process_genre_preferences(genres)
    user_preference = current_user.user_preference || current_user.build_user_preference
    user_preference.update(favorite_genres: genres)
  end

  def user_preference_params
    params.require(:user_preference).permit(:personality_profiles, favorite_genres: [])
  end

  def survey_params
    params.permit(personality_responses: {}, favorite_genres: [])
  end

  def show_welcome_modal?
    current_user.survey_responses.empty?
  end
end
