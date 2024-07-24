class SurveysController < ApplicationController
  before_action :authenticate_user!

  def index
    @survey_questions = SurveyQuestion.all
  end

  def create
    responses_params.each do |response_param|
      SurveyResponse.create(response_param.merge(user: current_user))
    end

    process_personality_profile if all_responses_received?
    redirect_to edit_user_preference_path(current_user.user_preference), notice: 'Survey completed. Please update your preferences.'
  end

  private

  def responses_params
    params.require(:responses).map do |response|
      response.permit(:survey_question_id, :response)
    end
  end

  def all_responses_received?
    required_questions_count = SurveyQuestion.where(question_type: %w[openness conscientiousness extraversion agreeableness neuroticism]).count
    current_user.survey_responses.where(survey_question: SurveyQuestion.where(question_type: %w[openness conscientiousness extraversion agreeableness neuroticism])).count == required_questions_count
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
