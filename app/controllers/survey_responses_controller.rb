# frozen_string_literal: true

class SurveyResponsesController < ApplicationController
  before_action :authenticate_user!

  def process_responses(user, responses)
    Rails.logger.info("Processing #{responses.size} responses for user #{user.id}")
    
    ActiveRecord::Base.transaction do
      responses.each do |question_id, response|
        Rails.logger.info("Processing response for question #{question_id}: #{response}")
        
        # Skip if question doesn't exist
        question = SurveyQuestion.find_by(id: question_id)
        if question.nil?
          Rails.logger.warn("Question with ID #{question_id} not found, skipping")
          next
        end
        
        # Skip attention check questions
        if question.attention_check?
          Rails.logger.info("Skipping attention check question #{question_id}")
          next
        end
        
        # Ensure response is a valid integer between 1 and 5
        numeric_response = response.to_i
        if numeric_response < 1 || numeric_response > 5
          Rails.logger.warn("Invalid response value: #{response}, converting to integer in range 1-5")
          # Default to neutral if invalid
          numeric_response = 3
        end
        
        survey_response = SurveyResponse.find_or_initialize_by(
          user: user,
          survey_question_id: question_id
        )
        
        Rails.logger.info("Found existing response: #{survey_response.persisted?}, current value: #{survey_response.response}")
        
        survey_response.response = numeric_response.to_s
        
        if survey_response.changed?
          Rails.logger.info("Response changed, saving")
          survey_response.save!
        else
          Rails.logger.info("Response unchanged, not saving")
        end
      end
      
      process_personality_profile(user)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to process survey responses: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    false
  rescue StandardError => e
    Rails.logger.error "Error processing survey responses: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    false
  end

  private

  def process_personality_profile(user)
    Rails.logger.info("Processing personality profile for user #{user.id}")
    
    # Get all responses including the survey questions
    responses = user.survey_responses.includes(:survey_question)
    Rails.logger.info("Found #{responses.size} total responses")
    
    # Filter out attention check questions
    valid_responses = responses.reject { |r| r.survey_question.attention_check? }
    Rails.logger.info("Found #{valid_responses.size} valid responses after filtering out attention checks")
    
    # Calculate personality profile
    personality_profile = PersonalityProfileCalculator.calculate(valid_responses)
    Rails.logger.info("Calculated personality profile: #{personality_profile.inspect}")

    # Ensure user preference exists
    user.ensure_user_preference
    
    # Update user preference with personality profile
    result = user.user_preference.update!(personality_profiles: personality_profile)

    if result
      Rails.logger.info "Successfully updated personality profile for user #{user.id}"
    else
      Rails.logger.error "Failed to update personality profile for user #{user.id}"
    end

    GenerateRecommendationsJob.perform_now(user.user_preference.id)
  end
end
