# frozen_string_literal: true

class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_preference

  GENRE_MAPPING = {
    openness: %w[Science-Fiction Fantasy Animation],
    conscientiousness: %w[Drama Biography History],
    extraversion: %w[Comedy Action Adventure],
    agreeableness: %w[Romance Family Music],
    neuroticism: %w[Thriller Mystery Horror]
  }.freeze

  def index
    authorize :recommendation, :index?
    @user_preference = current_user.user_preference
    if @user_preference.personality_profiles.present? && @user_preference.favorite_genres.present?
      @genres_map = Genre.all.group_by(&:name).transform_values { |g| g.map(&:tmdb_id) }

      content = Content.includes(:genres).all
      @recommendations = calculate_recommendations(content)

      # Limit to top 100 matches
      @recommendations = @recommendations.first(100)

      @page = params[:page].present? ? params[:page].to_i : 1
      per_page = 15
      @total_pages = (@recommendations.length.to_f / per_page).ceil
      @recommendations = @recommendations.slice((@page - 1) * per_page, per_page)
    else
      redirect_to surveys_path, alert: 'Please complete the survey to get personalized recommendations.'
    end
  end

  def show
    authorize :recommendation, :show?
    @item = Content.includes(:genres).find_by(source_id: params[:id], content_type: params[:type])

    if @item
      if @item.trailer_url.nil?
        # Fetch detailed information from TMDB
        details = if @item.content_type == 'movie'
                    TmdbService.fetch_movie_details(@item.source_id)
                  else
                    TmdbService.fetch_tv_show_details(@item.source_id)
                  end

        # Update the item with new information
        @item.update(
          trailer_url: fetch_trailer_url(details['videos']['results']),
          runtime: details['runtime'] || details['episode_run_time']&.first,
          directors: details['credits']['crew'].select { |c| c['job'] == 'Director' }.map { |d| d['name'] }.join(','),
          cast: details['credits']['cast'].take(5).map { |c| c['name'] }.join(','),
          vote_count: details['vote_count']  # Add vote count
        )

        # Fetch genre names directly
        genre_names = details['genres'].map { |g| g['name'] }

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
          vote_count: @item.vote_count,  # Include vote count in the response
          overview: @item.description,
          trailer_url: @item.trailer_url,
          genres: genre_names,  # Include genres as strings
          credits: {
            crew: @item.directors.split(',').map { |name| { job: 'Director', name: name.strip } },
            cast: @item.cast.split(',').map { |name| { name: name.strip } }
          }
        }
      else
        render json: { error: 'Content not found' }, status: :not_found
      end
    end
  end

  private

  def ensure_user_preference
    current_user.ensure_user_preference
  end

  def calculate_recommendations(content)
    recommendations = content.reject { |item| item.adult && current_user.user_preference.disable_adult_content }.map do |item|
      {
        id: item.source_id,
        type: item.content_type,
        title: item.title,
        poster_path: item.poster_url,
        country: abbreviate_country(item.production_countries_array&.first&.dig('name')),
        release_year: item.release_year,
        genres: item.genres.pluck(:name),
        match_score: calculate_match_score(item),
        rating: item.vote_average
      }
    end
    recommendations.sort_by { |r| -r[:match_score] }
  end

  def calculate_match_score(item)
    genres = item.genres.pluck(:name)
    big_five_score = calculate_big_five_score(genres)
    favorite_genres_score = calculate_favorite_genres_score(genres)
    
    # Adjust the weights to maintain the quality of recommendations
    (big_five_score * 0.6) + (favorite_genres_score * 0.4)
  end

  def calculate_big_five_score(genres)
    profile = @user_preference.personality_profiles
    score = 0
    GENRE_MAPPING.each do |trait, trait_genres|
      match = (genres & trait_genres).size
      score += profile[trait.to_s].to_i * match * 2 # Increase the weight of personality matches
    end
    score
  end

  def calculate_favorite_genres_score(genres)
    favorite_genres = @user_preference.favorite_genres || []
    favorite_genres = favorite_genres.split(',') if favorite_genres.is_a?(String)
    favorite_genres = favorite_genres.map(&:strip).map(&:to_s)

    combined_genres = {
      'Sci-Fi & Fantasy' => ['Science Fiction', 'Fantasy'],
      'Action & Adventure' => %w[Action Adventure],
      'War & Politics' => %w[War Politics]
    }

    combined_genres.each do |combined, separates|
      favorite_genres << combined if favorite_genres.intersect?(separates)
    end

    (genres & favorite_genres).size * 5 # Increase the weight of favorite genre matches
  end

  def abbreviate_country(country)
    return 'USA' if country == 'United States of America'
    country
  end

  def fetch_trailer_url(videos)
    return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
    trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' }
    trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
  end
end
