# frozen_string_literal: true

require_relative '../../lib/tasks/tmdb_tasks'

class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_preference, only: [:index, :show, :check_status, :refresh]

  def index
    authorize :recommendation, :index?
    @user_preference = current_user.ensure_user_preference
    @page = params[:page].present? ? params[:page].to_i : 1
    per_page = 15
    @recommendations = load_recommendations(@page, per_page)
    set_watchlist_status(@recommendations)
    @total_pages = (@user_preference.recommended_content_ids.length.to_f / per_page).ceil

    respond_to do |format|
      format.html
      format.json do
        if @recommendations.empty?
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
    
    if @user_preference.processing?
      render json: { status: 'processing' }
    elsif @user_preference.recommended_content_ids.present?
      render json: { status: 'ready' }
    else
      render json: { status: 'error', message: 'No recommendations found' }
    end
  end

  def refresh
    authorize :recommendation, :refresh?
    
    begin
      @user_preference = current_user.user_preference || current_user.create_user_preference
      
      if @user_preference.personality_profiles.blank? || @user_preference.favorite_genres.blank?
        render json: { 
          status: 'error', 
          message: 'Please complete your profile preferences first' 
        }, status: :unprocessable_entity
        return
      end
      
      @user_preference.update(processing: true)
      GenerateRecommendationsJob.perform_later(@user_preference.id)
      
      render json: { status: 'processing' }
    rescue StandardError => e
      Rails.logger.error "Failed to refresh recommendations: #{e.message}"
      render json: { status: 'error', message: 'Failed to refresh recommendations' }
    end
  end

  private

  def set_user_preference
    @user_preference = current_user.user_preference || 
                      current_user.create_user_preference
  end

  def load_recommendations(page, per_page)
    offset = (page - 1) * per_page
    
    Rails.logger.info "Loading recommendations for user #{@user_preference.user_id}"
    Rails.logger.info "Total recommended IDs: #{@user_preference.recommended_content_ids.size}"
    Rails.logger.info "Unique recommended IDs: #{@user_preference.recommended_content_ids.uniq.size}"
    
    # Load all recommendations first
    all_recommendations = Content.where(id: @user_preference.recommended_content_ids)
    all_recommendations = all_recommendations.where(adult: [false, nil]) if @user_preference.disable_adult_content
    
    mapped_recommendations = all_recommendations.map do |content|
      # Use AI's confidence score if available, otherwise fall back to calculated score
      match_score = if @user_preference.use_ai
        @user_preference.recommendation_scores[content.id.to_s].to_f
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
        reason: @user_preference.recommendation_reasons[content.id.to_s]
      }
    end

    sorted_recommendations = mapped_recommendations.sort_by { |r| -r[:match_score] }
    sorted_recommendations[offset, per_page] || []
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
end
