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
    @user_preference = current_user.user_preference || current_user.build_user_preference
    authorize @user_preference
    if SurveyResponsesController.new.process_responses(current_user, params[:personality_responses])
      process_genre_preferences(params[:favorite_genres])
      redirect_to recommendations_path, notice: 'Survey completed successfully. Here are your recommendations!'
    else
      redirect_to surveys_path, alert: 'There was an error processing your survey. Please try again.'
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
end
