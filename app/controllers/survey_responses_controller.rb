# frozen_string_literal: true

class SurveyResponsesController < ApplicationController
  before_action :authenticate_user!

  def process_responses(user, responses)
    Rails.logger.info("Processing #{responses.size} responses for user #{user.id}")
    
    # Get all question IDs being answered
    question_ids = responses.keys.map(&:to_i)
    
    # Skip processing if no questions
    if question_ids.empty?
      Rails.logger.warn("No valid question IDs found in responses")
      return true
    end
    
    ActiveRecord::Base.transaction do
      # Process each response
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
        
        # Find or initialize a response record (this works with soft deletion)
        survey_response = user.survey_responses.find_or_initialize_by(survey_question_id: question_id)
        survey_response.response = numeric_response.to_s
        
        survey_response.save!
        Rails.logger.info("Saved response for question #{question_id}: #{numeric_response}")
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

  def create
    # Get the question and response from params
    question_id = params.dig(:survey_response, :question_id)
    response_value = params.dig(:survey_response, :response)

    Rails.logger.info("Processing response for question #{question_id}: #{response_value}")

    begin
      # Find the question
      question = SurveyQuestion.find_by(id: question_id)
      
      if question.nil?
        Rails.logger.error("Question #{question_id} not found")
        render json: { status: 'error', message: 'Question not found' }, status: :unprocessable_entity
        return
      end
      
      # Find or initialize the response (this works with soft deletion)
      survey_response = current_user.survey_responses.find_or_initialize_by(survey_question_id: question_id)
      
      # Convert response to a numeric value if needed
      if question.question_type == 'likert' || question.question_type == 'attention_check'
        value_map = {
          'Strongly_Disagree' => 1,
          'Disagree' => 2,
          'Neutral' => 3,
          'Agree' => 4,
          'Strongly_Agree' => 5
        }
        response_value = value_map[response_value].to_s if value_map.key?(response_value)
      end
      
      survey_response.response = response_value
      
      if survey_response.save
        Rails.logger.info("Response saved successfully")
        
        # Calculate progress
        total_questions = SurveyQuestion.where(survey_type: question.survey_type)
                                      .where.not(question_type: 'attention_check')
                                      .count
        
        answered_questions = current_user.survey_responses.joins(:survey_question)
                                       .where(survey_questions: { survey_type: question.survey_type })
                                       .where.not(survey_questions: { question_type: 'attention_check' })
                                       .count
        
        progress = total_questions > 0 ? (answered_questions.to_f / total_questions * 100).round : 0
        
        render json: { 
          status: 'success',
          message: 'Response saved successfully',
          progress: progress
        }
      else
        Rails.logger.error("Failed to save response: #{survey_response.errors.full_messages}")
        render json: { 
          status: 'error', 
          message: survey_response.errors.full_messages.join(', ') 
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("Error processing response: #{e.message}")
      render json: { 
        status: 'error', 
        message: 'An error occurred while saving your response' 
      }, status: :internal_server_error
    end
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
    
    # Generate personality profile using the service
    # Always force a recalculation to ensure fresh data, especially important for retakes
    personality_profile = PersonalityProfileService.generate_profile(user, true)
    Rails.logger.info("Generated personality profile: #{personality_profile.inspect}")

    # Ensure user preference exists
    user_preference = user.ensure_user_preference
    
    # Generate a new personality summary
    user_preference.personality_summary = PersonalitySummaryService.generate_summary(user)
    user_preference.save
    Rails.logger.info("Updated personality summary")
    
    # Update survey completion status
    update_survey_completion_status(user, user_preference)
    
    # The profile is already saved by the service
    
    # Mark recommendations as outdated if they exist
    user_recommendation = user.user_recommendation
    if user_recommendation&.recommended_content_ids.present?
      user_recommendation.update(recommendations_generated_at: nil)
    end
  end
  
  def update_survey_completion_status(user, user_preference)
    # Check current status
    basic_completed = user.basic_survey_completed?
    extended_completed = user.extended_survey_completed?
    extended_in_progress = user.extended_survey_in_progress?
    
    # Update the user preference with completion status
    user_preference.update(
      basic_survey_completed: basic_completed,
      extended_survey_completed: extended_completed,
      extended_survey_in_progress: extended_in_progress
    )
    
    Rails.logger.info("Updated survey completion status: basic=#{basic_completed}, extended=#{extended_completed}, in_progress=#{extended_in_progress}")
  end
end
