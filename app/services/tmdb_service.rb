class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  API_KEY = ENV.fetch('THEMOVIEDB_KEY')
  MAX_PAGES = 4 # Number of pages to fetch

  def self.fetch_popular_movies
    fetch_multiple_pages("#{BASE_URL}/movie/popular")
  end

  def self.fetch_popular_tv_shows
    fetch_multiple_pages("#{BASE_URL}/tv/popular")
  end

  def self.fetch_top_rated_movies
    fetch_multiple_pages("#{BASE_URL}/movie/top_rated")
  end

  def self.fetch_top_rated_tv_shows
    fetch_multiple_pages("#{BASE_URL}/tv/top_rated")
  end

  def self.fetch_upcoming_movies
    fetch_multiple_pages("#{BASE_URL}/movie/upcoming")
  end

  def self.fetch_movie_details(movie_id)
    url = "#{BASE_URL}/movie/#{movie_id}"
    response = HTTP.get(url, params: { api_key: API_KEY, language: 'en-US', append_to_response: 'credits,videos' })
    JSON.parse(response.body.to_s)
  end

  def self.fetch_tv_show_details(tv_id)
    url = "#{BASE_URL}/tv/#{tv_id}"
    response = HTTP.get(url, params: { api_key: API_KEY, language: 'en-US', append_to_response: 'credits,videos' })
    JSON.parse(response.body.to_s)
  end

  def self.fetch_genres
    movie_genres_url = "#{BASE_URL}/genre/movie/list"
    tv_genres_url = "#{BASE_URL}/genre/tv/list"

    movie_response = HTTP.get(movie_genres_url, params: { api_key: API_KEY, language: 'en-US' })
    movie_genres = JSON.parse(movie_response.body.to_s)['genres']

    tv_response = HTTP.get(tv_genres_url, params: { api_key: API_KEY, language: 'en-US' })
    tv_genres = JSON.parse(tv_response.body.to_s)['genres']

    genres = (movie_genres + tv_genres).uniq { |genre| genre['id'] }

    combined_genres = ['Sci-Fi & Fantasy', 'Action & Adventure', 'War & Politics']
    user_facing_genres = genres.reject { |genre| combined_genres.include?(genre['name']) }

    { all_genres: genres, user_facing_genres: user_facing_genres }
  end

  def self.fetch_multiple_pages(url, pages = MAX_PAGES, additional_params = {})
    results = []
    (1..pages).each do |page|
      params = { api_key: API_KEY, language: 'en-US', page: page }.merge(additional_params)
      response = HTTP.get(url, params: params)
      data = JSON.parse(response.body.to_s)
      results += data['results'].map { |item| item.merge('tmdb_last_update' => data['updated_at']) }
    end
    results
  end

  def self.fetch_details(id, type)
    if type == 'movie'
      fetch_movie_details(id)
    else
      fetch_tv_show_details(id)
    end
  end

  def self.fetch_movies_by_category(category)
    url = "#{BASE_URL}/movie/#{category}"
    fetch_multiple_pages(url)
  end

  def self.fetch_tv_shows_by_category(category)
    url = "#{BASE_URL}/tv/#{category}"
    fetch_multiple_pages(url)
  end

  def self.fetch_by_genre(genre_id, type)
    url = "#{BASE_URL}/discover/#{type}"
    fetch_multiple_pages(url, additional_params: { with_genres: genre_id })
  end

  def self.fetch_by_decade(start_year, end_year, type)
    url = "#{BASE_URL}/discover/#{type}"
    fetch_multiple_pages(url, additional_params: { 
      'primary_release_date.gte' => "#{start_year}-01-01",
      'primary_release_date.lte' => "#{end_year}-12-31"
    })
  end

  def self.fetch_movie_changes(start_date)
    fetch_changes('movie', start_date)
  end

  def self.fetch_tv_changes(start_date)
    fetch_changes('tv', start_date)
  end

  def self.fetch_changes(type, start_date)
    url = "#{BASE_URL}/#{type}/changes"
    params = {
      api_key: API_KEY,
      start_date: start_date.strftime('%Y-%m-%d'),
      end_date: Time.now.strftime('%Y-%m-%d')
    }
    
    response = HTTP.get(url, params: params)
    data = JSON.parse(response.body.to_s)
    
    data['results'].map { |item| [item['id'], type] }
  end

  private

  def self.fetch_multiple_pages(url, pages: MAX_PAGES, additional_params: {})
    results = []
    (1..pages).each do |page|
      params = { api_key: API_KEY, language: 'en-US', page: page }.merge(additional_params)
      response = HTTP.get(url, params: params)
      data = JSON.parse(response.body.to_s)
      results += data['results'].map { |item| item.merge('tmdb_last_update' => data['updated_at']) }
    end
    results
  end
end
