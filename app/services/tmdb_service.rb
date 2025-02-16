class TmdbService
  BASE_URL = 'https://api.themoviedb.org/3'
  API_KEY = ENV.fetch('THEMOVIEDB_KEY')
  MAX_PAGES = 35
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

      begin
        movie_response = rate_limited_request { HTTP.get(movie_genres_url, params: { api_key: API_KEY, language: 'en-US' }) }
        movie_genres = JSON.parse(movie_response.body.to_s)['genres'] || []
        Rails.logger.info "Fetched #{movie_genres.size} movie genres"

        tv_response = rate_limited_request { HTTP.get(tv_genres_url, params: { api_key: API_KEY, language: 'en-US' }) }
        tv_genres = JSON.parse(tv_response.body.to_s)['genres'] || []
        Rails.logger.info "Fetched #{tv_genres.size} TV genres"

        genres = (movie_genres + tv_genres).uniq { |genre| genre['id'] }
        combined_genres = ['Sci-Fi & Fantasy', 'Action & Adventure', 'War & Politics']
        user_facing_genres = genres.reject { |genre| combined_genres.include?(genre['name']) }

        { all_genres: genres, user_facing_genres: user_facing_genres }
      rescue => e
        Rails.logger.error "Error fetching genres: #{e.message}"
        { all_genres: [], user_facing_genres: [] }
      end
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
      id = id.to_i  # Convert string ID to integer
      type == 'movie' ? fetch_movie_details(id) : fetch_tv_show_details(id)
    end

    def fetch_movies_by_category(category, pages = MAX_PAGES)
      url = "#{BASE_URL}/movie/#{category}"
      fetch_multiple_pages(url, pages)
    end

    def fetch_tv_shows_by_category(category, pages = MAX_PAGES)
      url = "#{BASE_URL}/tv/#{category}"
      fetch_multiple_pages(url, pages)
    end

    def fetch_by_genre(genre_id, type, pages = MAX_PAGES)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, pages, { 
        with_genres: genre_id,
        'vote_count.gte': 50
      })
    end

    def fetch_by_decade(start_year, end_year, type, pages = MAX_PAGES)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, pages, { 
        'primary_release_date.gte': "#{start_year}-01-01",
        'primary_release_date.lte': "#{end_year}-12-31",
        'vote_count.gte': 50
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

    def fetch_by_keyword(keyword, type, pages = MAX_PAGES)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, pages, {
        with_keywords: keyword,
        'vote_count.gte': 100,
        'vote_average.gte': 6.0
      })
    end

    def fetch_by_language(language, type, pages = MAX_PAGES)
      url = "#{BASE_URL}/discover/#{type}"
      fetch_multiple_pages(url, pages, {
        with_original_language: language,
        'vote_count.gte': 50,
        'vote_average.gte': 6.0
      })
    end

    def search(params)
      query = URI.encode_www_form_component(params[:title])
      type = params[:type] || 'movie'
      year = params[:year]

      url = "#{BASE_URL}/search/#{type}?api_key=#{API_KEY}&query=#{query}"
      url += "&year=#{year}" if year

      response = rate_limited_request { HTTP.get(url) }
      return nil unless response&.status&.success?

      data = JSON.parse(response.body.to_s)
      return nil unless data['results']&.any?

      # Sort results by title similarity and vote count
      results = data['results'].sort_by do |result|
        title = result['title'] || result['name']
        similarity = calculate_similarity(title.downcase, params[:title].downcase)
        vote_count = result['vote_count'] || 0
        [-similarity, -vote_count] # Sort by highest similarity, then highest vote count
      end

      # Get the best match
      best_match = results.first
      
      Rails.logger.info "TMDB search for '#{params[:title]}' found #{results.size} results. Best match: '#{best_match['title'] || best_match['name']}'"
      
      # Fetch full details for the best match
      fetch_details(best_match['id'], type)
    end

    private

    def calculate_similarity(str1, str2)
      longer = [str1.length, str2.length].max
      return 1.0 if longer.zero?
      
      (longer - levenshtein_distance(str1, str2)) / longer.to_f
    end

    def levenshtein_distance(str1, str2)
      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }
      
      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }
      
      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i-1] == str2[j-1] ? 0 : 1
          matrix[i][j] = [
            matrix[i-1][j] + 1,
            matrix[i][j-1] + 1,
            matrix[i-1][j-1] + cost
          ].min
        end
      end
      
      matrix[str1.length][str2.length]
    end
  end
end
