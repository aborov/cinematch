class SurveysController < ApplicationController
  before_action :authenticate_user!

  def index
    @personality_questions = SurveyQuestion.all
    genres = TmdbService.fetch_genres
    @genres = genres[:user_facing_genres]
    @total_questions = @personality_questions.count + 1 # +1 for genre selection
  end

  def create
    process_personality_responses(params[:personality_responses])
    process_genre_preferences(params[:genre_preferences])

    redirect_to recommendations_path, notice: 'Survey completed. Here are your recommendations!'
  end

  private

  def process_personality_responses(responses)
    responses.each do |question_id, response|
      SurveyResponse.create(
        user: current_user,
        survey_question_id: question_id,
        response: response
      )
    end
    process_personality_profile
  end

  def process_genre_preferences(genres)
    user_preference = current_user.user_preference || current_user.build_user_preference
    user_preference.update(favorite_genres: genres)
  end

  def process_personality_profile
    responses = current_user.survey_responses.includes(:survey_question)
    personality_profile = calculate_personality_profile(responses)
    current_user.user_preference.update(personality_profiles: personality_profile)
  end

  def calculate_personality_profile(responses)
    traits = %w[openness conscientiousness extraversion agreeableness neuroticism]
    profile = {}

    traits.each do |trait|
      trait_responses = responses.select { |r| r.survey_question.question_type == trait }
      average_score = trait_responses.map { |r| r.response.to_i }.sum / trait_responses.size.to_f
      profile[trait] = average_score.round(2)
    end

    profile
  end
end
