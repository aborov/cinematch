class RecommendationsController < ApplicationController
  before_action :authenticate_user!

  # Genre mapping for Big Five personality traits
  GENRE_MAPPING = {
    openness: %w[Science-Fiction Fantasy Animation],
    conscientiousness: %w[Drama Biography History],
    extraversion: %w[Comedy Action Adventure],
    agreeableness: %w[Romance Family Music],
    neuroticism: %w[Thriller Mystery Horror]
  }.freeze

  def index
    @user_preference = current_user.user_preference
    if @user_preference.personality_profiles.present?
      genres = Genre.all
      @genres_map = genres.group_by(&:name).transform_values { |g| g.map(&:tmdb_id) }

      movies = TmdbService.fetch_popular_movies + TmdbService.fetch_top_rated_movies + TmdbService.fetch_upcoming_movies
      tv_shows = TmdbService.fetch_popular_tv_shows + TmdbService.fetch_top_rated_tv_shows
      content = (movies + tv_shows).uniq { |item| item['id'] }
      @recommendations = calculate_recommendations(content)
    else
      redirect_to survey_responses_path, alert: 'Please complete the survey to receive recommendations.'
    end
  end

  def show
    @item = if params[:type] == 'movie'
              TmdbService.fetch_movie_details(params[:id])
            else
              TmdbService.fetch_tv_show_details(params[:id])
            end
    render json: @item
  end

  private

  def calculate_recommendations(content)
    recommendations = content.map do |item|
      {
        id: item['id'],
        type: item['media_type'] || (item['title'] ? 'movie' : 'tv'),
        title: item['title'] || item['name'],
        match_score: calculate_match_score(item)
      }
    end
    recommendations.sort_by { |r| -r[:match_score] }
  end

  def calculate_match_score(item)
    genre_ids = item['genre_ids']
    genres = genre_ids.flat_map { |id| @genres_map.keys.select { |k| @genres_map[k].include?(id) } }.uniq
    big_five_score = calculate_big_five_score(genres)
    favorite_genres_score = calculate_favorite_genres_score(genres)
    (big_five_score * 0.7) + (favorite_genres_score * 0.3)
  end

  def calculate_big_five_score(genres)
    profile = @user_preference.personality_profiles
    score = 0
    GENRE_MAPPING.each do |trait, trait_genres|
      match = (genres & trait_genres).size
      score += profile[trait.to_s] * match
    end
    score
  end

  def calculate_favorite_genres_score(genres)
    (genres & @user_preference.favorite_genres).size
  end
end
