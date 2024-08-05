class RecommendationsController < ApplicationController
  before_action :authenticate_user!

  GENRE_MAPPING = {
    openness: %w[Science-Fiction Fantasy Animation],
    conscientiousness: %w[Drama Biography History],
    extraversion: %w[Comedy Action Adventure],
    agreeableness: %w[Romance Family Music],
    neuroticism: %w[Thriller Mystery Horror],
  }.freeze

  def index
    @user_preference = current_user.user_preference
    if @user_preference.personality_profiles.present?
      genres = TmdbService.fetch_genres[:all_genres]
      @genres_map = genres.group_by { |g| g["name"] }.transform_values { |g| g.map { |gg| gg["id"] } }

      movies = TmdbService.fetch_popular_movies + TmdbService.fetch_top_rated_movies + TmdbService.fetch_upcoming_movies
      tv_shows = TmdbService.fetch_popular_tv_shows + TmdbService.fetch_top_rated_tv_shows
      content = (movies + tv_shows).uniq { |item| item["id"] }
      @recommendations = calculate_recommendations(content)
      @page = params[:page].present? ? params[:page].to_i : 1
    per_page = 15
    @total_pages = (@recommendations.length.to_f / per_page).ceil
    @recommendations = @recommendations.slice((@page - 1) * per_page, per_page)
    else
      redirect_to surveys_path, alert: "Please complete the survey to receive recommendations."
    end
  end

  def show
    @item = if params[:type] == "movie"
        TmdbService.fetch_movie_details(params[:id])
      else
        TmdbService.fetch_tv_show_details(params[:id])
      end
    render json: @item
  end

  private

  def calculate_recommendations(content)
    recommendations = content.map do |item|
      details = fetch_details(item["id"], item["media_type"] || (item["title"] ? "movie" : "tv"))
      {
        id: item["id"],
        type: item["media_type"] || (item["title"] ? "movie" : "tv"),
        title: item["title"] || item["name"],
        poster_path: item["poster_path"],
        country: abbreviate_country(details["production_countries"]&.first&.dig("name")),
        release_year: (item["release_date"] || item["first_air_date"])&.split("-")&.first,
        genres: details["genres"]&.map { |g| g["name"] },
        match_score: calculate_match_score(item),
        rating: details["vote_average"], # Include TMDb rating
      }
    end
    recommendations.sort_by { |r| -r[:match_score] }
  end

  def fetch_details(id, type)
    if type == "movie"
      TmdbService.fetch_movie_details(id)
    else
      TmdbService.fetch_tv_show_details(id)
    end
  end

  def calculate_match_score(item)
    genre_ids = item["genre_ids"]
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
      score += profile[trait.to_s].to_i * match # Ensure the value is converted to integer
    end
    score
  end

  def calculate_favorite_genres_score(genres)
    favorite_genres = @user_preference.favorite_genres || []
    
    # Split the favorite_genres if it's a String
    if favorite_genres.is_a?(String)
      favorite_genres = favorite_genres.split(',')
    end
    
    favorite_genres = favorite_genres.map(&:strip).map(&:to_s) # Ensure all genres are strings and remove whitespace
  
    combined_genres = {
      "Sci-Fi & Fantasy" => ["Science Fiction", "Fantasy"],
      "Action & Adventure" => ["Action", "Adventure"],
      "War & Politics" => ["War", "Politics"],
    }
    
    combined_genres.each do |combined, separates|
      if (favorite_genres & separates).any?
        favorite_genres << combined
      end
    end
    
    return (genres & favorite_genres).size
  end

  def abbreviate_country(country)
    return "USA" if country == "United States of America"
    country
  end
end
