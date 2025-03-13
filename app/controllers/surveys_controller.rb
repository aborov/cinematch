# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_preference
  before_action :set_survey_type

  def index
    @survey_type = params[:type] || 'basic'
    @questions = SurveyQuestion.where(survey_type: @survey_type)
                              .where.not(question_type: 'attention_check')
                              .order(Arel.sql('RANDOM()')).to_a

    # Add attention check questions strategically
    attention_checks = SurveyQuestion.where(question_type: 'attention_check')
    
    # Debug attention check questions
    Rails.logger.debug "Attention check questions: #{attention_checks.map { |q| { id: q.id, text: q.question_text, correct_answer: q.correct_answer } }}"
    
    if @survey_type == 'basic'
      # For basic survey, add one attention check in the middle
      middle_check = attention_checks.first
      insert_position = @questions.length / 2
      @questions.insert(insert_position, middle_check) if middle_check
      
      # Debug inserted attention check
      Rails.logger.debug "Inserted attention check at position #{insert_position}: #{middle_check&.attributes}"
    else
      # For extended survey, add two attention checks at 1/3 and 2/3 points
      extended_checks = attention_checks.offset(1).limit(2).to_a
      first_third = @questions.length / 3
      second_third = first_third * 2
      @questions.insert(first_third, extended_checks[0]) if extended_checks[0]
      @questions.insert(second_third, extended_checks[1]) if extended_checks[1]
    end

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
    
    Rails.logger.info("Processing survey submission for user #{current_user.id}")
    Rails.logger.info("Survey params: #{survey_params.inspect}")
    
    if process_survey_responses
      Rails.logger.info("Survey responses processed successfully")
      
      # Use the handle_successful_submission method for both survey types
      handle_successful_submission
    else
      handle_failed_submission
    end
  end

  def results
    @survey_type = params[:type] || 'basic'
    @user_preference = current_user.ensure_user_preference
    
    # Generate and store the personality profile if needed
    @personality_profile = PersonalityProfileService.generate_profile(current_user)
    
    authorize :survey, :results?
    
    # Queue recommendation generation in the background
    # Only queue if recommendations are outdated or don't exist
    # if @user_preference.recommendations_outdated? || @user_preference.recommended_content_ids.blank?
    #   Rails.logger.info("Queueing recommendation generation for user #{current_user.id}")
    #   GenerateRecommendationsJob.perform_later(@user_preference.id)
    #   Rails.logger.info("Recommendation generation job queued successfully")
    # else
    #   Rails.logger.info("Using existing recommendations for user #{current_user.id}")
    # end
  end

  def save_progress
    authorize :survey, :save_progress?
    
    begin
      Rails.logger.info("Save progress params: #{params.inspect}")
      
      ActiveRecord::Base.transaction do
        if params[:survey_response]
          question_id = params[:survey_response][:question_id]
          response_value = params[:survey_response][:response].to_s
          
          Rails.logger.info("Processing response for question #{question_id} with value #{response_value}")
          
          # Skip saving attention check responses
          question = SurveyQuestion.find_by(id: question_id)
          if question.nil?
            Rails.logger.error("Question with ID #{question_id} not found")
            render json: { status: 'error', message: "Question not found" }, status: :not_found
            return
          end
          
          Rails.logger.info("Question type: #{question.question_type}, Attention check: #{question.attention_check?}")
          
          if question && question.attention_check?
            Rails.logger.info("Skipping saving attention check response for question #{question_id}")
            render json: { status: 'success', message: 'Attention check response not saved' }
            return
          end
          
          Rails.logger.info("Looking for existing response for user #{current_user.id} and question #{question_id}")
          survey_response = current_user.survey_responses
            .where(survey_question_id: question_id)
            .first_or_initialize
          
          Rails.logger.info("Response found: #{survey_response.persisted?}, Current value: #{survey_response.response}")
          
          # Ensure response_value is a valid integer between 1 and 5
          numeric_value = response_value.to_i
          if numeric_value < 1 || numeric_value > 5
            Rails.logger.warn("Invalid response value: #{response_value}, converting to integer in range 1-5")
            # Map the RESPONSE_VALUES from JavaScript to integers 1-5
            case response_value
            when "1" then numeric_value = 1 # Strongly_Disagree
            when "2" then numeric_value = 2 # Disagree
            when "3" then numeric_value = 3 # Neutral
            when "4" then numeric_value = 4 # Agree
            when "5" then numeric_value = 5 # Strongly_Agree
            else
              numeric_value = 3 # Default to Neutral if invalid
            end
          end
          
          survey_response.response = numeric_value.to_s
          
          if survey_response.changed?
            Rails.logger.info("Response changed, saving with validate: false")
            survey_response.save!(validate: false)
            Rails.logger.info("Response saved successfully")
          else
            Rails.logger.info("Response unchanged, not saving")
          end
        else
          Rails.logger.warn("No survey_response parameter found in request")
        end
      end
      
      render json: { status: 'success' }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Record Invalid: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("Error saving survey response: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { status: 'error', message: e.message }, status: :internal_server_error
    end
  end

  private

  def set_survey_type
    @survey_type = params[:type] == 'extended' ? 'extended' : 'basic'
  end

  def calculate_survey_progress
    completed = current_user.survey_responses.count
    total = SurveyQuestion.where(survey_type: @survey_type).where.not(question_type: 'attention_check').count
    (completed.to_f / total * 100).round
  end

  def process_survey_responses
    personality_responses = survey_params[:personality_responses]&.to_h || {}
    favorite_genres = survey_params[:favorite_genres] || []
    
    Rails.logger.info("Processing survey responses: #{personality_responses.inspect}")
    Rails.logger.info("Favorite genres: #{favorite_genres.inspect}")
    
    # Ensure all responses are stored as strings
    personality_responses.transform_values! { |v| v.to_s }
    
    survey_response_controller = SurveyResponsesController.new
    if survey_response_controller.process_responses(current_user, personality_responses)
      Rails.logger.info("Successfully processed survey responses")
      @user_preference.update(favorite_genres: favorite_genres) if @survey_type == 'basic'
      true
    else
      Rails.logger.error("Failed to process survey responses")
      false
    end
  end

  def handle_successful_submission
    # Queue recommendation generation in the background
    # GenerateRecommendationsJob.perform_later(@user_preference.id)
    
    # Redirect to results page instead of recommendations
    redirect_to survey_results_path(type: @survey_type), 
                notice: @survey_type == 'basic' ? 
                  'Basic survey completed! View your personality profile and initial recommendations.' : 
                  'Extended survey completed! View your comprehensive personality profile and personalized recommendations.'
  end

  def handle_failed_submission
    flash[:alert] = "There was a problem processing your survey responses. Please try again."
    redirect_to surveys_path(type: @survey_type)
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
    params.permit(:authenticity_token, :type, personality_responses: {}, favorite_genres: [])
  end

  def show_welcome_modal?
    current_user.survey_responses.empty?
  end
end
