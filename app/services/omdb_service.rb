class OmdbService
  API_KEY = ENV.fetch('OMDB_API_KEY', nil)
  BASE_URL = 'http://www.omdbapi.com/'
  
  class << self
    def fetch_movies(batch_size = 20)
      begin
        Rails.logger.info("Fetching #{batch_size} movies from OMDB")
        
        # Since OMDB doesn't have a "popular" endpoint, we'll search for movies by year
        # starting with recent years
        processed_count = 0
        current_year = Time.now.year
        
        # Try to fetch movies from the last 5 years
        (0..4).each do |year_offset|
          break if processed_count >= batch_size
          
          year = current_year - year_offset
          search_results = search_by_year(year)
          
          search_results.each do |movie_data|
            break if processed_count >= batch_size
            
            imdb_id = movie_data['imdbID']
            
            # Skip if we already have this movie
            next if Content.exists?(external_id: imdb_id, content_type: 'movie')
            
            # Fetch detailed information
            details = fetch_movie_details(imdb_id)
            
            # Skip if we couldn't get details
            next unless details['Response'] == 'True'
            
            # Create the content record
            Content.create!(
              title: details['Title'],
              description: details['Plot'],
              release_date: details['Released'],
              poster_path: details['Poster'],
              content_type: 'movie',
              external_id: imdb_id,
              vote_average: details['imdbRating'].to_f,
              vote_count: details['imdbVotes'].gsub(',', '').to_i,
              runtime: details['Runtime'].to_i,
              genres: details['Genre'],
              raw_data: details.to_json
            )
            
            processed_count += 1
          end
        end
        
        { success: true, processed: processed_count, total: batch_size }
      rescue => e
        Rails.logger.error("Error in OmdbService.fetch_movies: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        { success: false, error: e.message }
      end
    end
    
    def search_by_year(year)
      return [] unless API_KEY
      
      url = "#{BASE_URL}?apikey=#{API_KEY}&s=movie&type=movie&y=#{year}"
      response = HTTP.get(url)
      data = JSON.parse(response.body.to_s)
      
      if data['Response'] == 'True' && data['Search'].is_a?(Array)
        data['Search']
      else
        []
      end
    rescue => e
      Rails.logger.error("Error searching OMDB by year #{year}: #{e.message}")
      []
    end
    
    def fetch_movie_details(imdb_id)
      return {} unless API_KEY
      
      url = "#{BASE_URL}?apikey=#{API_KEY}&i=#{imdb_id}"
      response = HTTP.get(url)
      JSON.parse(response.body.to_s)
    rescue => e
      Rails.logger.error("Error fetching OMDB movie details for #{imdb_id}: #{e.message}")
      {}
    end
  end
end 
