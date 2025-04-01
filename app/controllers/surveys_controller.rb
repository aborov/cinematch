# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_preference
  before_action :set_survey_type

  def index
    authorize :survey, :index?
    logger.debug "Current user ID: #{current_user.id}"
    logger.debug "User basic survey completed: #{current_user.basic_survey_completed?}"
    logger.debug "User extended survey completed: #{current_user.extended_survey_completed?}"
    
    # Determine which survey to show - normalize the type to symbol
    @survey_type = (params[:type] || 'basic').to_sym
    logger.debug "Survey type requested: #{@survey_type}"
    
    # Track retake parameter to pass to the view
    @retake = params[:retake] == 'true'
    logger.debug "Retaking survey: #{@retake}"
    
    # Save retake status in session for when the form is submitted
    if @retake
      session[:retaking_survey] = @survey_type.to_s
      logger.debug "Saved retaking status in session for #{@survey_type}"
    end
    
    # Get or create the user preference
    @user_preference = current_user.ensure_user_preference
    
    # --- START REVISED QUESTION ORDERING LOGIC ---
    # Fetch all questions and user responses first
    all_questions = SurveyQuestion.where(survey_type: @survey_type).where.not(question_type: 'attention_check').order(:id) # Consistent base order
    attention_checks = SurveyQuestion.where(survey_type: @survey_type, question_type: 'attention_check').order(:id)
    @user_responses = current_user.responses_for_survey(@survey_type)
    @saved_responses = @user_responses

    # Clear saved responses if retaking
    if @retake
      @saved_responses = {}
      logger.debug "Cleared saved responses for retake"
    end
    
    # Partition questions based on saved responses (use string keys for comparison)
    answered_question_ids = @saved_responses.keys.map(&:to_s)
    answered_questions = []
    unanswered_questions = []

    all_questions.each do |q|
      if answered_question_ids.include?(q.id.to_s)
        answered_questions << q
      else
        unanswered_questions << q
      end
    end

    # Shuffle the unanswered questions
    unanswered_questions.shuffle!

    # Add attention checks randomly into the unanswered portion
    # (Simple approach: add to end of unanswered and shuffle again)
    # TODO: Refine insertion logic if specific placement (1/3, 2/3) is strictly needed *within* unanswered
    unanswered_questions += attention_checks.shuffle 
    unanswered_questions.shuffle!

    # Combine the lists
    @questions = answered_questions + unanswered_questions
    
    # Set total regular questions count for JS
    @total_questions = all_questions.size 
    logger.debug "Total regular questions: #{@total_questions}"
    logger.debug "Total questions including attention checks: #{@questions.size}"
    logger.debug "Answered: #{answered_questions.size}, Unanswered (incl. attention): #{unanswered_questions.size}"
    # --- END REVISED QUESTION ORDERING LOGIC ---

    # Calculate progress for the view (based on regular questions)
    completed_count = answered_questions.size
    @progress = @total_questions > 0 ? (completed_count.to_f / @total_questions * 100).round : 0
    logger.debug "Calculated progress: #{@progress}% (#{completed_count}/#{@total_questions})"
    
    # Set genres for basic survey
    @genres = Genre.user_facing_genres if @survey_type.to_s == 'basic'
    
    # Determine whether to show welcome modal
    @show_welcome_modal = show_welcome_modal?
  end

  def create
    @user_preference = current_user.ensure_user_preference
    authorize :survey, :create?
    
    # Get the survey type from params, checking multiple places
    @survey_type = params[:survey_type] || params[:type] || 'basic'
    @survey_type = @survey_type.to_s
    
    # Get retake status from session
    is_retake = session[:retaking_survey] == @survey_type
    
    logger.debug "Processing survey submission for user #{current_user.id} - Survey type: #{@survey_type}"
    logger.debug "Survey params: #{survey_params.inspect}"
    logger.debug "Submit survey flag: #{params[:submit_survey]}"
    logger.debug "Is retake: #{is_retake}"
    
    # Add more detailed logging for debugging
    if request.format.json? || request.content_type == 'application/json'
      logger.debug "JSON request detected"
      logger.debug "Full params: #{params.inspect}"
      logger.debug "Favorite genres from params: #{params[:favorite_genres].inspect}"
      logger.debug "Survey responses from params: #{params[:survey_responses].inspect}"
    end
    
    if process_survey_responses
      logger.debug "Survey responses processed successfully"
      
      # Check if this is a final submission of the survey
      if params[:submit_survey] == 'true'
        logger.debug "Final survey submission detected"
        # Add retake param to handle_successful_submission
        params[:retake] = is_retake.to_s
        handle_successful_submission
      else
        # Just a normal save during the survey process
        logger.debug "Regular response submission (not final)"
        flash[:notice] = "Responses saved successfully!"
        redirect_to surveys_path(type: @survey_type)
      end
    else
      handle_failed_submission
    end
  end

  def results
    # First authorize this action before any potential redirects
    authorize :survey, :results?
    
    @user = current_user
    @survey_type = params[:type] || session[:completed_survey_type] || 'basic'
    @user_preference = @user.ensure_user_preference
    
    # Check if the survey was just completed (from session flag)
    @survey_just_completed = session.delete(:survey_just_completed)
    session.delete(:completed_survey_type) # Clean up
    
    # Get current survey status (uses cached values if available)
    @basic_completed = @user.basic_survey_completed?
    @extended_completed = @user.extended_survey_completed?
    
    logger.debug "Survey results page for User #{@user.id}: Basic completed: #{@basic_completed}, Extended completed: #{@extended_completed}, Just completed: #{@survey_just_completed}, Survey type: #{@survey_type}"
    
    # Only redirect if not coming from survey completion
    if !@basic_completed && !@survey_just_completed
      redirect_to surveys_path(type: 'basic')
      return
    elsif @survey_type == 'extended' && !@extended_completed && !@survey_just_completed
      # If they haven't completed extended survey but are viewing extended results,
      # and didn't just complete it, switch them to basic results
      @survey_type = 'basic'
    end
    
    # Generate profile if basic survey is completed or just completed
    if @basic_completed || @survey_just_completed
      @personality_profile = PersonalityProfileService.generate_profile(@user, true)
      logger.debug "User #{@user.id} profile generation: #{@personality_profile.present?}"
      
      # Only queue recommendation generation if we just completed a survey or have no recommendations
      user_recommendation = @user.user_recommendation || @user.build_user_recommendation
      if @survey_just_completed || 
         user_recommendation.recommended_content_ids.blank? && 
         user_recommendation.recommendation_scores.blank?
        # Don't wait for recommendations to be generated - just queue the job
        if !user_recommendation.processing?
          logger.debug "Generating recommendations for user #{@user.id} after survey completion"
          user_recommendation.update(processing: true)
          GenerateRecommendationsJob.perform_later(@user.id)
        end
      end
    end
    
    render :results
  end

  def save_progress
    # Add Pundit authorization
    authorize :survey, :save_progress?
    
    # For debugging
    Rails.logger.info("Survey progress params: #{params.inspect}")
    
    return unless current_user
    
    begin
      # Extract values from either JSON or form-encoded formats
      params_json = request.format.json? ? params : nil
      
      # Get survey type, defaulting to basic
      survey_type = params[:type].present? ? params[:type] : "basic"
      Rails.logger.info("Setting survey type to: #{survey_type}")
      
      # Check if we're saving a full progress update
      if params[:save_progress] && params[:save_progress] == true
        Rails.logger.info("Full progress save requested for #{survey_type} survey")

        # --- START ADDED LOGIC FOR EXTENDED RETAKE ---
        if survey_type == "extended" && current_user.user_preference.extended_survey_completed?
          Rails.logger.info("Detected save progress for a COMPLETED extended survey. Resetting completion status and clearing old responses for user #{current_user.id}.")
          # This is the first save action since completing the survey, treat as start of retake.
          current_user.user_preference.update_columns(
            extended_survey_completed: false,
            extended_survey_in_progress: true
          )
          # Delete all previous responses for this survey type
          current_user.survey_responses.joins(:survey_question).where(survey_questions: { survey_type: :extended }).destroy_all
          Rails.logger.info("Cleared previous extended survey responses for user #{current_user.id}.")
        end
        # --- END ADDED LOGIC FOR EXTENDED RETAKE ---
        
        # Process multiple responses if provided
        if params[:survey_responses].present?
          process_batch_responses(params[:survey_responses], survey_type)
        end
        
        # Update in-progress flag (safe to call again even if set above)
        if survey_type == "extended"
          current_user.user_preference.update_column(:extended_survey_in_progress, true)
          Rails.logger.info("Ensured extended_survey_in_progress flag is true for user #{current_user.id}")
        end
        
        # Get progress percentage
        completed_count = current_user.survey_responses.joins(:survey_question)
                                 .where(survey_questions: { survey_type: survey_type })
                                 .where.not(survey_questions: { question_type: 'attention_check' }).count
        
        total_count = SurveyQuestion.where(survey_type: survey_type)
                                .where.not(question_type: 'attention_check').count
        
        progress_percentage = total_count > 0 ? (completed_count.to_f / total_count * 100).round : 0
        
        render json: { 
          status: 'success', 
          message: 'Progress saved successfully',
          progress: progress_percentage,
          completed: completed_count,
          total: total_count
        }
      # Legacy path for handling single response (can be removed later)
      elsif params[:survey_response].present?
        # This is a single question response update
        question_id = params[:survey_response][:question_id]
        response_value = params[:survey_response][:response]
        
        Rails.logger.info("Saving response for question #{question_id}: #{response_value}")
        
        save_single_response(question_id, response_value, survey_type)
      # Handle multiple responses submission
      elsif params[:survey_responses].present?
        Rails.logger.info("Processing batch of #{params[:survey_responses].size} responses")
        process_batch_responses(params[:survey_responses], survey_type)
        
        render json: { status: 'success', message: 'Responses saved successfully' }
      else
        Rails.logger.error("Invalid parameters for saving progress")
        render json: { status: 'error', message: 'Invalid parameters' }, status: :unprocessable_entity
      end
      
    rescue ActionController::InvalidAuthenticityToken => e
      Rails.logger.error("CSRF token validation failed: #{e.message}")
      render json: { status: 'error', message: 'Your session has expired. Please refresh the page.' }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error("Error saving progress: #{e.message}")
      render json: { status: 'error', message: 'An error occurred' }, status: :unprocessable_entity
    end
  end

  # Helper method to process multiple responses at once
  def process_batch_responses(responses_array, survey_type)
    # Log the size and type of responses_array
    Rails.logger.debug("Processing batch responses: size=#{responses_array.try(:size) || 'nil'}, type=#{responses_array.class.name}")
    Rails.logger.debug("Full responses_array content: #{responses_array.inspect}")
    
    # Initialize counter for saved responses
    saved_count = 0
    
    # Normalize responses_array to an array of hashes with symbol keys
    normalized_responses = case responses_array
      when Hash
        Rails.logger.debug("Converting Hash to array with single item")
        [responses_array.symbolize_keys]
      when ActionController::Parameters
        Rails.logger.debug("Converting ActionController::Parameters to array")
        [responses_array.to_unsafe_h.symbolize_keys]
      when Array
        Rails.logger.debug("Processing Array of responses")
        responses_array.map do |resp|
          case resp
          when Hash
            resp.symbolize_keys
          when ActionController::Parameters
            resp.to_unsafe_h.symbolize_keys
          else
            Rails.logger.warn("Unexpected response type in array: #{resp.class.name}")
            resp
          end
        end
      else
        Rails.logger.error("Unexpected responses_array type: #{responses_array.class.name}")
        []
    end
    
    Rails.logger.debug("Normalized responses: #{normalized_responses.inspect}")
    
    return if normalized_responses.blank?
    
    # Process each response within a transaction
    ActiveRecord::Base.transaction do
      normalized_responses.each do |response_params|
        begin
          question_id = response_params[:question_id]
          response_value = response_params[:response]
          
          Rails.logger.debug("Processing response: question_id=#{question_id}, value=#{response_value}")
          
          if question_id.blank? || response_value.blank?
            Rails.logger.warn("Missing data in response: #{response_params.inspect}")
            next
          end
          
          question = SurveyQuestion.find_by(id: question_id)
          unless question
            Rails.logger.warn("Question not found with ID: #{question_id}")
            next
          end
          
          # Save the response
          response = current_user.survey_responses.where(survey_question_id: question_id).first_or_initialize
          response.response = response_value
          response.save!
          saved_count += 1
          
          Rails.logger.debug("Saved response for question #{question_id}: #{response_value}")
        rescue => e
          Rails.logger.error("Error processing response: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          raise # Re-raise to trigger transaction rollback
        end
      end
    end
    
    # Log the total number of responses saved
    Rails.logger.info("Successfully saved #{saved_count} responses out of #{normalized_responses.size} processed")
    
    # Update completion status
    check_survey_completion(survey_type)
    
    # Return true to indicate success
    true
  rescue => e
    Rails.logger.error("Failed to process batch responses: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end
  
  # Helper method to save a single response
  def save_single_response(question_id, response_value, survey_type)
    # Find the question
    question = SurveyQuestion.find_by(id: question_id)
    
    if question.nil?
      Rails.logger.error("Question #{question_id} not found")
      render json: { status: 'error', message: 'Question not found' }, status: :unprocessable_entity
      return
    end
    
    # Find or create a response
    survey_response = current_user.survey_responses.find_or_initialize_by(survey_question_id: question_id)
    
    # Convert response to a numeric value if needed
    if question.question_type == 'likert'
      if %w[Strongly_Disagree Disagree Neutral Agree Strongly_Agree].include?(response_value)
        # Map text values to numbers
        value_map = {
          'Strongly_Disagree' => 1,
          'Disagree' => 2, 
          'Neutral' => 3,
          'Agree' => 4,
          'Strongly_Agree' => 5
        }
        numeric_value = value_map[response_value]
        
        survey_response.response = numeric_value.to_s
      else
        # Assume it's already a numeric value
        numeric_value = response_value.to_i
        survey_response.response = numeric_value.to_s
      end
    else
      # For non-likert questions, store as-is
      survey_response.response = response_value.to_s
    end
    
    if survey_response.save
      Rails.logger.info("Successfully saved response: #{survey_response.id} with value #{survey_response.response}")
      
      # Update in-progress flag for extended survey
      if question.survey_type == 'extended'
        check_survey_completion(survey_type)
      end
      
      # Get progress percentage for response
      completed_count = current_user.survey_responses.joins(:survey_question)
                             .where(survey_questions: { survey_type: survey_type })
                             .where.not(survey_questions: { question_type: 'attention_check' }).count
      
      total_count = SurveyQuestion.where(survey_type: survey_type)
                          .where.not(question_type: 'attention_check').count
      
      progress_percentage = total_count > 0 ? (completed_count.to_f / total_count * 100).round : 0
      
      render json: { 
        status: 'success', 
        message: 'Response saved successfully', 
        response_id: survey_response.id,
        progress: progress_percentage,
        completed: completed_count,
        total: total_count
      }
    else
      Rails.logger.error("Failed to save response: #{survey_response.errors.full_messages.join(', ')}")
      render json: { status: 'error', message: 'Failed to save response' }, status: :unprocessable_entity
    end
  end
  
  # Helper method to check and update survey completion status
  def check_survey_completion(survey_type)
    # For extended survey, check completion status and update flag
    if survey_type == 'extended'
      # Check if extended survey is completed
      total_questions = SurveyQuestion.where(survey_type: 'extended')
                                     .where.not(question_type: 'attention_check').count
                                     
      user_responses = current_user.survey_responses.joins(:survey_question)
                                  .where(survey_questions: { survey_type: 'extended' })
                                  .where.not(survey_questions: { question_type: 'attention_check' }).count
                                  
      # Completion threshold (100% for now)
      completion_threshold = 1.0
      completion_ratio = user_responses.to_f / total_questions
      
      Rails.logger.info("Extended survey completion check: #{user_responses}/#{total_questions} (#{(completion_ratio * 100).round}%)")
      
      is_completed = completion_ratio >= completion_threshold
      
      # Always set in_progress to true if there are any responses but not complete
      current_user.user_preference.update(
        extended_survey_completed: is_completed,
        extended_survey_in_progress: !is_completed && user_responses > 0
      )
      
      Rails.logger.info("Updated extended survey status: completed=#{is_completed}, in_progress=#{!is_completed && user_responses > 0}")
    end
  end

  private

  def set_survey_type
    # Normalize the survey type to always be a string and set it from params
    @survey_type = (params[:type] || 'basic').to_s
    logger.debug "Setting survey type to: #{@survey_type}"
  end

  def calculate_survey_progress
    # Only count responses for questions of this survey type
    survey_questions = SurveyQuestion.where(survey_type: @survey_type).where.not(question_type: 'attention_check')
    completed = current_user.survey_responses.joins(:survey_question)
                           .where(survey_questions: { survey_type: @survey_type })
                           .where.not(survey_questions: { question_type: 'attention_check' })
                           .count
    total = survey_questions.count
    return 0 if total == 0
    (completed.to_f / total * 100).round
  end

  def process_survey_responses
    # Look for survey responses in the newer format first
    if params[:survey_responses].present?
      logger.debug "Processing batch of #{params[:survey_responses].is_a?(Hash) ? params[:survey_responses].size : 'unknown number of'} responses"
      logger.debug "survey_responses parameter type: #{params[:survey_responses].class.name}"
      logger.debug "survey_responses raw: #{params[:survey_responses].inspect}"
      
      # Handle both JSON and form-encoded formats
      responses_array = params[:survey_responses]
      
      # If it's a Hash with numeric keys (from JSON params), convert to array
      if responses_array.is_a?(Hash)
        logger.debug "Converting responses hash to array"
        responses_array = responses_array.values
      end
      
      # If it's ActionController::Parameters, convert to array
      if responses_array.is_a?(ActionController::Parameters)
        logger.debug "Converting ActionController::Parameters to array"
        responses_array = responses_array.to_unsafe_h.values
      end
      
      logger.debug "Responses after conversion: #{responses_array.inspect}"
      
      # Track the structure of the responses to help debugging
      if responses_array.is_a?(Array) && responses_array.first
        first_response = responses_array.first
        logger.debug "First response type: #{first_response.class.name}"
        logger.debug "First response structure: #{first_response.inspect}"
      end
      
      # Process the batch of responses
      process_batch_responses(responses_array, @survey_type)
      
      # Process genre preferences for basic survey
      if @survey_type == 'basic' && params[:favorite_genres].present?
        logger.debug "Processing genre preferences: #{params[:favorite_genres].inspect}"
        process_genre_preferences(params[:favorite_genres])
      end
      
      return true
    
    # Fall back to legacy format if present
    elsif survey_params[:personality_responses].present?
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
        return true
      else
        Rails.logger.error("Failed to process survey responses")
        return false
      end
    end
    
    # No valid response format found
    logger.error("No valid responses found in params")
    logger.error("Available params keys: #{params.keys}")
    false
  end

  def handle_successful_submission
    # Get the survey type from params, defaulting to basic
    survey_type = (params[:survey_type] || params[:type] || 'basic').to_s
    logger.debug "Handling successful submission for survey type: #{survey_type}"
    
    # Check if this is a retake
    is_retake = params[:retake] == 'true'
    logger.debug "Is retake: #{is_retake}"
    
    # Force update the user_preference with survey completion status
    if survey_type == 'basic'
      logger.debug "Setting basic survey as completed for user #{current_user.id}"
      
      # Get favorite genres from params
      favorite_genres = params[:favorite_genres] || []
      
      # Handle case where it might be a nested hash (Rails JSON parsing)
      if favorite_genres.is_a?(Hash)
        logger.debug "Converting favorite_genres hash to array"
        favorite_genres = favorite_genres.values
      end
      
      logger.debug "Favorite genres for update: #{favorite_genres.inspect}"
      
      # Update completion status and genre preferences
      current_user.user_preference.update(
        basic_survey_completed: true,
        favorite_genres: favorite_genres
      )
      logger.debug "Set basic_survey_completed to true for user #{current_user.id}"
      
    elsif survey_type == 'extended'
      logger.debug "Setting extended survey as completed for user #{current_user.id}"
      # Count responses to verify we have enough
      total_questions = SurveyQuestion.where(survey_type: 'extended')
                                     .where.not(question_type: 'attention_check').count
      
      user_responses = current_user.survey_responses.joins(:survey_question)
                                  .where(survey_questions: { survey_type: 'extended' })
                                  .where.not(survey_questions: { question_type: 'attention_check' }).count
      
      logger.debug "Extended survey completion check: #{user_responses}/#{total_questions}"
      
      # Only mark as completed if all questions are answered (95% threshold)
      completion_threshold = 0.95 # 95% completion is enough
      completion_ratio = user_responses.to_f / total_questions
      
      if completion_ratio >= completion_threshold
        current_user.user_preference.update(
          extended_survey_completed: true,
          extended_survey_in_progress: false
        )
        logger.debug "Set extended_survey_completed to true for user #{current_user.id}"
      else
        logger.warn "Not all extended survey questions answered (#{user_responses}/#{total_questions})"
        current_user.user_preference.update(
          extended_survey_in_progress: true
        )
      end
    end
    
    # Generate personality profile
    if survey_type == 'basic' || (survey_type == 'extended' && current_user.basic_survey_completed?)
      begin
        logger.debug "Generating personality profile for user #{current_user.id}"
        profile = PersonalityProfileService.generate_profile(current_user)
        
        if profile
          logger.debug "Profile generated successfully"
          
          # Set session flags for survey completion
          session[:survey_just_completed] = true
          session[:completed_survey_type] = survey_type
          
          # For API requests (AJAX), respond with JSON
          if request.format.json? || request.content_type == 'application/json'
            # Make sure the user has a valid user preference record
            current_user.ensure_user_preference
            
            # Force reload the user to ensure we have the latest data
            current_user.reload
            
            logger.debug "User preference after profile generation: basic_completed=#{current_user.user_preference.basic_survey_completed}, extended_completed=#{current_user.user_preference.extended_survey_completed}"
            
            render json: { 
              status: 'success', 
              message: 'Survey completed successfully',
              redirect_url: survey_results_path(type: survey_type)
            }
          else
            # For form submissions, redirect
            redirect_to survey_results_path(type: survey_type)
          end
        else
          logger.error "Failed to generate personality profile"
          
          if request.format.json? || request.content_type == 'application/json'
            render json: { status: 'error', message: "We couldn't generate your personality profile. Please try again later." }, status: :unprocessable_entity
          else
            flash[:alert] = "We couldn't generate your personality profile. Please try again later."
            redirect_to surveys_path(type: survey_type)
          end
        end
      rescue => e
        logger.error "Error generating personality profile: #{e.message}"
        logger.error e.backtrace.join("\n")
        
        if request.format.json? || request.content_type == 'application/json'
          render json: { status: 'error', message: "An error occurred while processing your survey. Please try again later." }, status: :unprocessable_entity
        else
          flash[:alert] = "An error occurred while processing your survey. Please try again later."
          redirect_to surveys_path(type: survey_type)
        end
      end
    else
      # No profile to generate, just redirect
      if request.format.json? || request.content_type == 'application/json'
        render json: { 
          status: 'success', 
          message: 'Survey saved successfully',
          redirect_url: surveys_path(type: survey_type)
        }
      else
        redirect_to surveys_path(type: survey_type)
      end
    end
  end

  def handle_failed_submission
    flash[:alert] = "There was a problem processing your survey responses. Please try again."
    redirect_to surveys_path(type: @survey_type)
  end

  def ensure_user_preference
    @user_preference = current_user.ensure_user_preference
  end

  def process_genre_preferences(genres)
    logger.debug "Processing genre preferences: #{genres.inspect}"
    
    # Handle different formats of the genres parameter
    if genres.is_a?(Hash)
      logger.debug "Converting genres hash to array"
      genres = genres.values
    end
    
    # Ensure genres is an array
    genres = Array(genres)
    
    logger.debug "Genres after conversion: #{genres.inspect}"
    
    user_preference = current_user.user_preference || current_user.build_user_preference
    user_preference.update(favorite_genres: genres)
    
    logger.debug "Updated user_preference favorite_genres: #{user_preference.favorite_genres.inspect}"
  end

  def user_preference_params
    params.require(:user_preference).permit(:personality_profiles, favorite_genres: [])
  end

  def survey_params
    # Core permitted parameters
    params.permit(
      :authenticity_token, 
      :type, 
      :submit_survey, 
      :save_progress,
      :retake,
      personality_responses: {}, 
      favorite_genres: [], 
      survey_responses: [:question_id, :response]
    )
  end

  def show_welcome_modal?
    # Show welcome modal if the user has no responses AND the modal hasn't been shown in this session
    # Don't show if it's a retake
    retaking_survey = params[:retake] == 'true'
    current_user.survey_responses.empty? && !session[:welcome_modal_shown] && !retaking_survey
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

  # Add attention check questions based on survey type
  def add_attention_check_questions(questions, survey_type)
    # Get all attention check questions
    attention_checks = SurveyQuestion.where(question_type: :attention_check).to_a
    
    # Return original questions if no attention checks available
    return questions if attention_checks.empty?
    
    # Shuffle attention checks to randomize them
    attention_checks.shuffle!
    
    if survey_type == :basic
      # For basic survey, insert only one attention check question in the middle
      middle_position = questions.size / 2
      questions.insert(middle_position, attention_checks.first)
    else
      # For extended survey, insert two attention check questions at 1/3 and 2/3 points
      first_position = questions.size / 3
      second_position = (questions.size * 2) / 3
      
      questions.insert(first_position, attention_checks[0])
      questions.insert(second_position, attention_checks[1] || attention_checks[0])
    end
    
    questions
  end
end
