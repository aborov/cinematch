class SurveyResponsesController < ApplicationController
  before_action :authenticate_user!

  def process_responses(user, responses)
    ActiveRecord::Base.transaction do
      responses.each do |question_id, response|
        SurveyResponse.create!(
          user: user,
          survey_question_id: question_id,
          response: response
        )
      end
      process_personality_profile(user)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to process survey responses: #{e.message}"
    false
  end
  
  # def index
  #   @survey_questions = SurveyQuestion.all
  # end

  # def create
  #   responses_params.each do |question_id, response_param|
  #     permitted_response = ActionController::Parameters.new(response_param).permit(:response, :survey_question_id)
  #     SurveyResponse.create(permitted_response.merge(user_id: current_user.id, survey_question_id: question_id))
  #   end

  #   ensure_user_preference_exists
  #   process_personality_profile if all_responses_received?
  #   redirect_to edit_user_preference_path(current_user.user_preference), notice: 'Survey completed. Please update your preferences.'
  # end

  private

  # def responses_params
  #   params.require(:responses).to_unsafe_h
  # end

  # def all_responses_received?
  #   required_questions_count = SurveyQuestion.where(question_type: %w[openness conscientiousness extraversion agreeableness neuroticism]).count
  #   current_user.survey_responses.where(survey_question: SurveyQuestion.where(question_type: %w[openness conscientiousness extraversion agreeableness neuroticism])).count == required_questions_count
  # end

  # def ensure_user_preference_exists
  #   current_user.create_user_preference! unless current_user.user_preference
  # end

  def process_personality_profile(user)
    responses = user.survey_responses.includes(:survey_question)
    personality_profile = calculate_personality_profile(responses)
    Rails.logger.debug "Calculated Personality Profile: #{personality_profile.inspect}"
    
    user.ensure_user_preference
    result = user.user_preference.update!(personality_profiles: personality_profile)
    
    if result
      Rails.logger.info "Successfully updated personality profile for user #{user.id}"
    else
      Rails.logger.error "Failed to update personality profile for user #{user.id}"
    end
  end

  def calculate_personality_profile(responses)
    traits = %w[openness conscientiousness extraversion agreeableness neuroticism]
    profile = {}

    traits.each do |trait|
      trait_responses = responses.select { |r| r.survey_question.question_type == trait }
      if trait_responses.any?
        average_score = trait_responses.map { |r| r.response.to_i }.sum / trait_responses.size.to_f
        profile[trait] = average_score.round(2)
      else
        Rails.logger.warn "No responses found for trait: #{trait}"
      end
    end

    profile
  end
end
