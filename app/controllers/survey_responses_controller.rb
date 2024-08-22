# frozen_string_literal: true

class SurveyResponsesController < ApplicationController
  before_action :authenticate_user!

  def process_responses(user, responses)
    ActiveRecord::Base.transaction do
      responses.each do |question_id, response|
        SurveyResponse.create!(
          user:,
          survey_question_id: question_id,
          response:
        )
      end
      process_personality_profile(user)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to process survey responses: #{e.message}"
    false
  end

  private

  def process_personality_profile(user)
    responses = user.survey_responses.includes(:survey_question)
    personality_profile = PersonalityProfileCalculator.calculate(responses)
    Rails.logger.debug "Calculated Personality Profile: #{personality_profile.inspect}"

    user.ensure_user_preference
    result = user.user_preference.update!(personality_profiles: personality_profile)

    if result
      Rails.logger.info "Successfully updated personality profile for user #{user.id}"
    else
      Rails.logger.error "Failed to update personality profile for user #{user.id}"
    end
  end
end
