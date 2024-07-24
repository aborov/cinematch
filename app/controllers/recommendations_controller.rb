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
      movies = TmdbService.fetch_popular_movies
      tv_shows = TmdbService.fetch_popular_tv_shows
      content = movies + tv_shows
      @recommendations = calculate_recommendations(content)
    else
      redirect_to survey_responses_path, alert: 'Please complete the survey to receive recommendations.'
    end
  end

  private

  def calculate_recommendations(content)
    recommendations = content.map do |item|
      {
        title: item['title'] || item['name'],
        match_score: calculate_match_score(item)
      }
    end
    recommendations.sort_by { |r| -r[:match_score] }
  end

  def calculate_match_score(item)
    genres = item['genre_ids'].map { |id| Genre.find_by(tmdb_id: id).name }
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
