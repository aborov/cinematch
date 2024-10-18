# frozen_string_literal: true

require_relative '../../lib/tasks/tmdb_tasks'

class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_preference, only: [:index]

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
    @item = Content.find_by(id: params[:id])

    if @item
      if @item.trailer_url.nil? || @item.runtime.nil?
        details = TmdbService.fetch_details(@item.source_id, @item.content_type)
        TmdbTasks.update_content_batch([details])
        @item.reload
      end

      genre_names = @item.genre_names

      render json: {
        id: @item.source_id,
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
    @page = 1
    per_page = 15
    recommendations = load_recommendations(@page, per_page)
    
    if recommendations.present?
      render json: { status: 'ready' }
    else
      render json: { status: 'processing' }
    end
  end

  private

  def set_user_preference
    @user_preference = current_user.user_preference || current_user.build_user_preference
  end

  def load_recommendations(page, per_page)
    offset = (page - 1) * per_page
    content_ids = @user_preference.recommended_content_ids[offset, per_page] || []

    Content.where(id: content_ids).map do |content|
      Rails.logger.debug "Content ID: #{content.id}, Poster URL: #{content.poster_url}"
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
        match_score: @user_preference.calculate_match_score(content.genre_ids_array)
      }
    end
  end

  def set_watchlist_status(recommendations)
    watchlist_items = current_user.watchlist_items.pluck(:source_id, :content_type, :watched)
    recommendations.each do |recommendation|
      watchlist_item = watchlist_items.find { |item| item[0] == recommendation[:source_id].to_s && item[1] == recommendation[:content_type] }
      recommendation[:in_watchlist] = !watchlist_item.nil?
      recommendation[:watched] = watchlist_item&.last || false
    end
  end
end
