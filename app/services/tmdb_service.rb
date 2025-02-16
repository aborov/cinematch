class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  API_KEY = ENV.fetch('THEMOVIEDB_KEY')
  MAX_PAGES = 10
  RATE_LIMIT = 45 # Requests per second
  RATE_LIMIT_WINDOW = 1 # second

  @request_times = []

  include CircuitBreaker
  
  circuit_breaker(
    failure_threshold: 5,
    reset_timeout: 1.hour,
    monitor_timeout: 10.seconds,
    error_handler: ->(e) { Rails.logger.error("Circuit breaker tripped: #{e.message}") }
  )

  class << self
    def rate_limited_request(max_retries = 3)
      with_circuit_breaker do
        retries = 0
        begin
          sleep(0.25) # Rate limiting
          yield
        rescue OpenSSL::SSL::SSLError, HTTP::ConnectionError => e
          if retries < max_retries
            retries += 1
            sleep_time = 2**retries
            Rails.logger.warn("SSL Error occurred, retrying in #{sleep_time}s (#{retries}/#{max_retries}): #{e.message}")
            sleep(sleep_time)
            retry
          else
            Rails.logger.error("Failed after #{max_retries} retries: #{e.message}")
            raise
          end
        end
      end
    end

    def fetch_popular_movies
      fetch_multiple_pages("#{BASE_URL}/movie/popular")
    end

    def fetch_popular_tv_shows
      fetch_multiple_pages("#{BASE_URL}/tv/popular")
    end

    def fetch_top_rated_movies
      fetch_multiple_pages("#{BASE_URL}/movie/top_rated")
    end

    def fetch_top_rated_tv_shows
      fetch_multiple_pages("#{BASE_URL}/tv/top_rated")
    end

    def fetch_upcoming_movies
      fetch_multiple_pages("#{BASE_URL}/movie/upcoming")
    end

    def fetch_movie_details(movie_id)
      url = "#{BASE_URL}/movie/#{movie_id}"
      response = rate_limited_request { HTTP.get(url, params: { api_key: API_KEY, language: 'en-US', append_to_response: 'credits,videos,keywords,external_ids' }) }
      JSON.parse(response.body.to_s)
    end

    def fetch_tv_show_details(tv_id)
      url = "#{BASE_URL}/tv/#{tv_id}"
      response = rate_limited_request { HTTP.get(url, params: { api_key: API_KEY, language: 'en-US', append_to_response: 'credits,videos,keywords,external_ids' }) }
      JSON.parse(response.body.to_s)
    end

    def fetch_genres
      movie_genres_url = "#{BASE_URL}/genre/movie/list"
      tv_genres_url = "#{BASE_URL}/genre/tv/list"

      movie_response = rate_limited_request { HTTP.get(movie_genres_url, params: { api_key: API_KEY, language: 'en-US' }) }
      movie_genres = JSON.parse(movie_response.body.to_s)['genres']

      tv_response = rate_limited_request { HTTP.get(tv_genres_url, params: { api_key: API_KEY, language: 'en-US' }) }
      tv_genres = JSON.parse(tv_response.body.to_s)['genres']

      genres = (movie_genres + tv_genres).uniq { |genre| genre['id'] }

      combined_genres = ['Sci-Fi & Fantasy', 'Action & Adventure', 'War & Politics']
      user_facing_genres = genres.reject { |genre| combined_genres.include?(genre['name']) }

      { all_genres: genres, user_facing_genres: user_facing_genres }
    end

    def fetch_multiple_pages(url, pages = MAX_PAGES, additional_params = {})
      results = []
      (1..pages).each do |page|
        params = { api_key: API_KEY, language: 'en-US', page: page }.merge(additional_params)
        response = rate_limited_request { HTTP.get(url, params: params) }
        data = JSON.parse(response.body.to_s)
        
        if data['results'].is_a?(Array)
          results += data['results']
        elsif data['keywords'].is_a?(Array)
          results += data['keywords']
        else
          puts "Warning: 'results' or 'keywords' key not found or not an array in API response for URL: #{url}"
          break
        end
        
        break if data['page'] >= data['total_pages']
      end
      results
    end

    def fetch_details(id, type)
      type == 'movie' ? fetch_movie_details(id) : fetch_tv_show_details(id)
    end

    def fetch_movies_by_category(category)
      url = "#{BASE_URL}/movie/#{category}"
      fetch_multiple_pages(url)
    end

    def fetch_tv_shows_by_category(category)
      url = "#{BASE_URL}/tv/#{category}"
      fetch_multiple_pages(url)
    end

    def fetch_by_genre(genre_id, type)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, MAX_PAGES, { with_genres: genre_id })
    end

    def fetch_by_decade(start_year, end_year, type)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, MAX_PAGES, { 
        'primary_release_date.gte' => "#{start_year}-01-01",
        'primary_release_date.lte' => "#{end_year}-12-31"
      })
    end

    def fetch_movie_changes(start_date)
      fetch_changes('movie', start_date)
    end

    def fetch_tv_changes(start_date)
      fetch_changes('tv', start_date)
    end

    def fetch_changes(type, start_date)
      url = "#{BASE_URL}/#{type}/changes"
      all_results = []
      page = 1
      
      loop do
        params = {
          api_key: API_KEY,
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: Time.now.strftime('%Y-%m-%d'),
          page: page
        }
        
        response = rate_limited_request { HTTP.get(url, params: params) }
        data = JSON.parse(response.body.to_s)
        
        all_results.concat(data['results'].map { |item| [item['id'], type] })
        
        break if page >= data['total_pages'] || page >= 10  # Limit to 10 pages (2000 results) to avoid excessive API calls
        page += 1
      end
      
      all_results
    end
  end
end
