require 'net/http'
require 'json'

class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  API_KEY = ENV.fetch('THEMOVIEDB_KEY')

  def self.fetch_popular_movies
    url = "#{BASE_URL}/movie/popular?api_key=#{API_KEY}&language=en-US&page=1"
    response = Net::HTTP.get(URI(url))
    JSON.parse(response)['results']
  end

  def self.fetch_popular_tv_shows
    url = "#{BASE_URL}/tv/popular?api_key=#{API_KEY}&language=en-US&page=1"
    response = Net::HTTP.get(URI(url))
    JSON.parse(response)['results']
  end
end
