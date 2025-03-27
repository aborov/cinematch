# frozen_string_literal: true

require_relative '../../lib/tasks/tmdb_tasks'

class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_preference, only: [:index, :show, :check_status, :refresh]
  before_action :set_user_recommendation, only: [:index, :show, :check_status, :refresh]

  def index
    authorize :recommendation, :index?
    
    # Check if user has completed the basic survey
    logger.debug "Checking if user #{current_user.id} has completed basic survey: #{current_user.basic_survey_completed?}"
    
    basic_completed = current_user.basic_survey_completed?
    
    # Force recalculation if needed (check database directly as a fallback)
    if !basic_completed
      responses_count = current_user.survey_responses.joins(:survey_question)
                                  .where(survey_questions: { survey_type: 'basic' })
                                  .where.not(survey_questions: { question_type: 'attention_check' })
                                  .count
      
      basic_questions_count = SurveyQuestion.where(survey_type: 'basic')
                                          .where.not(question_type: 'attention_check')
                                          .count
      
      logger.debug "Fallback count: #{responses_count} responses out of #{basic_questions_count} questions"
      
      # Consider completed if at least 70% done
      if basic_questions_count > 0 && (responses_count.to_f / basic_questions_count) >= 0.7
        logger.debug "Survey actually appears to be completed based on response count"
        current_user.user_preference.update_column(:basic_survey_completed, true)
        basic_completed = true
      end
    end
    
    unless basic_completed
      logger.debug "User #{current_user.id} has not completed basic survey, redirecting"
      redirect_to surveys_path(type: 'basic')
      return
    end
    
    # Check if we need to force clear the processing flag
    if @user_recommendation.processing? && (Time.current - @user_recommendation.updated_at) > 10.minutes
      logger.info "Processing flag stuck for user #{current_user.id}, resetting"
      @user_recommendation.update_column(:processing, false)
    end
    
    # CRITICAL: If we have scores but no content_ids, fix this first
    if @user_recommendation.recommended_content_ids.nil? && 
       @user_recommendation.recommendation_scores.present?
      logger.info "User #{current_user.id} has scores but no content_ids, fixing"
      @user_recommendation.fix_missing_content_ids
      @user_recommendation.reload
    end
    
    # Check if there are any recommendations at all
    has_recommendations = @user_recommendation.recommended_content_ids.present? || 
                          @user_recommendation.recommendation_scores.present?
    
    # Instead of using ensure_recommendations which can trigger regeneration,
    # just check if we're already processing or need to start
    if @user_recommendation.processing?
      @processing = true
      logger.info "Recommendations for user #{current_user.id} are already being processed"
      
      # If we also have recommendations, show them while processing continues
      if has_recommendations
        @processing = false
        logger.info "Showing existing recommendations while new ones are being processed"
      else
        # No recommendations available yet
        @recommendations = []
        @total_pages = 0
        @page = 1
        
        respond_to do |format|
          format.html
          format.json do
            render json: { status: 'processing' }
          end
        end
        return
      end
    elsif !has_recommendations
      # Only start processing if specifically forced or if we have no recommendations at all
      @processing = true
      logger.info "No recommendations found for user #{current_user.id}, starting generation"
      
      # Force regeneration only if we have no recommendations at all
      @user_recommendation.update(processing: true)
      GenerateRecommendationsJob.perform_later(current_user.id)
      
      @recommendations = []
      @total_pages = 0
      @page = 1
      
      respond_to do |format|
        format.html
        format.json do
          render json: { status: 'processing' }
        end
      end
      return
    else
      @processing = false
    end
    
    # We have recommendations, show them
    @page = params[:page].present? ? params[:page].to_i : 1
    per_page = 15
    
    # Get all recommendations to calculate total pages
    @all_recommendations = load_all_recommendations_count
    @total_pages = (@all_recommendations.to_f / per_page).ceil
    
    # Load the recommendations for the current page
    @recommendations = load_recommendations(@page, per_page)
    set_watchlist_status(@recommendations)
    
    if @recommendations.empty? && @user_recommendation.recommendation_scores.present?
      # Try one more time to fix content_ids
      logger.info "Empty recommendations but have scores, trying to fix for user #{current_user.id}"
      @user_recommendation.fix_missing_content_ids
      @user_recommendation.reload
      # Try loading recommendations again
      @recommendations = load_recommendations(@page, per_page)
      set_watchlist_status(@recommendations)
    end

    respond_to do |format|
      format.html
      format.json do
        if @processing
          render json: { status: 'processing' }
        elsif @recommendations.empty?
          render json: { status: 'error', message: "We're having trouble displaying your recommendations. Please try refreshing the page." }
        else
          render json: { 
            status: 'ready', 
            html: render_to_string(partial: 'recommendations_list', locals: { recommendations: @recommendations, total_pages: @total_pages, current_page: @page }),
            total_pages: @total_pages,
            current_page: @page
          }
        end
      end
    end
  end

  def show
    authorize :recommendation, :show?
    @item = Content.find_by(source_id: params[:id], content_type: params[:type])

    if @item
      if @item.trailer_url.nil? || @item.runtime.nil?
        details = TmdbService.fetch_details(@item.source_id, @item.content_type)
        TmdbTasks.update_content_batch([details])
        @item.reload
      end

      genre_names = @item.genre_names

      render json: {
        id: @item.id,
        source_id: @item.source_id,
        title: @item.title,
        name: @item.title,
        poster_path: @item.poster_url,
        runtime: @item.runtime,
        release_date: @item.release_year.to_s,
        first_air_date: @item.release_year.to_s,
        production_countries: JSON.parse(@item.production_countries || '[]'),
        vote_average: @item.vote_average,
        vote_count: @item.vote_count,
        overview: @item.description,
        trailer_url: @item.trailer_url,
        genres: genre_names,
        credits: {
          crew: @item.directors.split(',').map { |name| { job: 'Director', name: name.strip } },
          cast: @item.cast.split(',').map { |name| { name: name.strip } }
        },
        number_of_seasons: @item.number_of_seasons,
        number_of_episodes: @item.number_of_episodes,
        in_production: @item.in_production,
        creators: @item.creators&.split(',')&.map(&:strip),
        spoken_languages: JSON.parse(@item.spoken_languages || '[]'),
        content_type: @item.content_type
      }
    else
      Rails.logger.error("Content not found: source_id=#{params[:id]}, content_type=#{params[:type]}")
      render json: { error: 'Content not found' }, status: :not_found
    end
  end

  def check_status
    authorize :recommendation, :check_status?
    
    # Clear stuck processing flag if needed (older than 5 minutes)
    if @user_recommendation.processing? && (Time.current - @user_recommendation.updated_at) > 5.minutes
      logger.info "Resetting stuck processing flag for user #{current_user.id} in check_status"
      
      begin
        ActiveRecord::Base.connection.execute(
          "UPDATE user_recommendations SET processing = false WHERE id = #{@user_recommendation.id}"
        )
      rescue => e 
        logger.error "Failed to reset processing flag: #{e.message}"
      end
      
      @user_recommendation.reload
    end
    
    # Check if recommendations exist
    has_recommendations = @user_recommendation.recommended_content_ids.present? || 
                         @user_recommendation.recommendation_scores.present?
    
    if @user_recommendation.processing?
      # If processing for too long with existing recommendations, show what we have
      if has_recommendations && (Time.current - @user_recommendation.updated_at) > 30.seconds
        logger.info "Processing taking too long, showing existing recommendations for user #{current_user.id}"
        # Fix content_ids if needed
        if @user_recommendation.recommended_content_ids.blank? && @user_recommendation.recommendation_scores.present?
          @user_recommendation.fix_missing_content_ids
        end
        render json: { status: 'ready' }
      else
        render json: { status: 'processing' }
      end
    elsif has_recommendations
      # If we have scores but no content_ids, fix it
      if @user_recommendation.recommended_content_ids.blank? && @user_recommendation.recommendation_scores.present?
        @user_recommendation.fix_missing_content_ids
      end
      render json: { status: 'ready' }
    else
      render json: { status: 'error', message: 'No recommendations found' }
    end
  end

  def refresh
    authorize :recommendation, :refresh?
    
    begin
      if @user_preference.personality_profiles.blank? || @user_preference.favorite_genres.blank?
        render json: { 
          status: 'error', 
          message: 'Please complete your profile preferences first' 
        }, status: :unprocessable_entity
        return
      end
      
      # Explicitly mark recommendations as outdated
      @user_recommendation.mark_as_outdated!
      
      # Start processing
      @user_recommendation.update(processing: true)
      GenerateRecommendationsJob.perform_later(current_user.id)
      
      render json: { status: 'processing' }
    rescue StandardError => e
      Rails.logger.error "Failed to refresh recommendations: #{e.message}"
      render json: { status: 'error', message: 'Failed to refresh recommendations' }
    end
  end

  private

  def set_user_preference
    @user_preference = current_user.user_preference || current_user.create_user_preference
  end

  def set_user_recommendation
    @user_recommendation = current_user.user_recommendation || current_user.create_user_recommendation
  end

  def load_recommendations(page, per_page)
    offset = (page - 1) * per_page
    
    logger.info "Loading recommendations for user #{current_user.id}"
    
    # Get recommendation IDs using the helper method that handles all formats
    content_ids = @user_recommendation.get_all_content_ids
    
    if content_ids.empty? && @user_recommendation.recommendation_scores.present?
      # Try to recover using the scores if available
      content_ids = @user_recommendation.recommendation_scores.keys.map(&:to_i)
      logger.info "Recovered #{content_ids.size} IDs from scores"
      
      # Try to fix the content_ids for next time
      if content_ids.present?
        @user_recommendation.fix_missing_content_ids
      end
    end
    
    # Return early if no content IDs
    if content_ids.empty?
      logger.warn "No content IDs found for user #{current_user.id}"
      return []
    end
    
    logger.info "Total recommended IDs: #{content_ids.size}"
    logger.info "Unique recommended IDs: #{content_ids.uniq.size}"
    
    # Load all recommendations
    all_recommendations = Content.where(id: content_ids)
    all_recommendations = all_recommendations.where(adult: [false, nil]) if @user_preference.disable_adult_content
    
    logger.info "Found #{all_recommendations.size} content records"
    
    mapped_recommendations = all_recommendations.map do |content|
      # Use AI's confidence score if available, otherwise fall back to calculated score
      match_score = if @user_preference.use_ai
        @user_recommendation.recommendation_scores[content.id.to_s].to_f
      else
        @user_preference.calculate_match_score(content.genre_ids_array) || 0
      end
      
      {
        id: content.id,
        source_id: content.source_id,
        content_type: content.content_type,
        title: content.title,
        poster_url: content.poster_url,
        production_countries: content.production_countries_array,
        release_year: content.release_year,
        genres: Genre.where(tmdb_id: content.genre_ids_array).pluck(:name),
        vote_average: content.vote_average,
        match_score: match_score,
        reason: @user_recommendation.recommendation_reasons[content.id.to_s]
      }
    end

    sorted_recommendations = mapped_recommendations.sort_by { |r| -r[:match_score] }
    result = sorted_recommendations[offset, per_page] || []
    
    logger.info "Returning #{result.size} recommendations for page #{page}"
    result
  end

  def set_watchlist_status(recommendations)
    watchlist_items = current_user.watchlist_items.pluck(:source_id, :content_type, :watched, :rating)
    recommendations.each do |recommendation|
      watchlist_item = watchlist_items.find { |item| item[0] == recommendation[:source_id].to_s && item[1] == recommendation[:content_type] }
      if watchlist_item
        recommendation[:in_watchlist] = true
        recommendation[:watched] = watchlist_item[2]
        recommendation[:rating] = watchlist_item[3]
      else
        recommendation[:in_watchlist] = false
        recommendation[:watched] = false
        recommendation[:rating] = nil
      end
    end
  end

  def load_all_recommendations_count
    # Get recommendation IDs using the helper method that handles all formats
    content_ids = @user_recommendation.get_all_content_ids
    
    if content_ids.empty? && @user_recommendation.recommendation_scores.present?
      # Fallback to scores if content_ids is missing
      content_ids = @user_recommendation.recommendation_scores.keys.map(&:to_i)
      logger.info "Recovered #{content_ids.size} IDs from scores"
    end
    
    if content_ids.empty?
      logger.warn "No content IDs found"
      return 0
    end
    
    logger.info "Total recommendations count: #{content_ids.size}"
    
    # Count valid content IDs
    query = Content.where(id: content_ids)
    query = query.where(adult: [false, nil]) if @user_preference.disable_adult_content
    query.count
  end
end
