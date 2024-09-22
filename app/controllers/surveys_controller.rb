# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_preference

  def index
    @personality_questions = SurveyQuestion.all
    puts "Number of questions: #{@personality_questions.count}"
    genres = TmdbService.fetch_genres
    @genres = genres[:user_facing_genres]
    @total_questions = @personality_questions.count + 1 # +1 for genre selection
    authorize :survey, :index?
  end

  def create
    @user_preference = current_user.ensure_user_preference
    authorize :survey, :create?
    personality_responses = survey_params[:personality_responses]&.to_h || {}
    favorite_genres = survey_params[:favorite_genres] || []

    survey_response_controller = SurveyResponsesController.new
    if survey_response_controller.process_responses(current_user, personality_responses)
      @user_preference.update(favorite_genres: favorite_genres)
      GenerateRecommendationsJob.perform_later(@user_preference.id)
      redirect_to recommendations_path, notice: 'Survey completed. Your recommendations are being generated!'
    else
      @personality_questions = SurveyQuestion.all
      genres = TmdbService.fetch_genres
      @genres = genres[:user_facing_genres]
      @total_questions = @personality_questions.count + 1
      render :index
    end
  end

  private

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
end
