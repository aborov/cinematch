require 'http'
require 'json'

class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  API_KEY = ENV.fetch('THEMOVIEDB_KEY')
  MAX_PAGES = 5 # Number of pages to fetch

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

    (movie_genres + tv_genres).uniq { |genre| genre['id'] }
  end

  private

  def self.fetch_multiple_pages(url)
    results = []
    (1..MAX_PAGES).each do |page|
      response = HTTP.get(url, params: { api_key: API_KEY, language: 'en-US', page: page })
      parsed_response = JSON.parse(response.body.to_s)
      results += parsed_response['results']
    end
    results
  end
end
