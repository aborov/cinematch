class FetcherServiceClient
  class << self
    def fetch_movies(provider, batch_size = nil)
      url = "#{fetcher_service_url}/fetcher/fetch"
      
      params = {
        provider: provider
      }
      
      params[:batch_size] = batch_size if batch_size.present?
      
      response = HTTParty.post(url, body: params)
      
      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error("Failed to fetch movies: #{response.code} - #{response.body}")
        { error: "Failed to fetch movies: #{response.code}" }
      end
    rescue => e
      Rails.logger.error("Error fetching movies: #{e.message}")
      { error: e.message }
    end
    
    def status
      url = "#{fetcher_service_url}/fetcher/status"
      
      response = HTTParty.get(url)
      
      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error("Failed to get fetcher status: #{response.code} - #{response.body}")
        { error: "Failed to get fetcher status: #{response.code}" }
      end
    rescue => e
      Rails.logger.error("Error getting fetcher status: #{e.message}")
      { error: e.message }
    end
    
    def wake
      url = "#{fetcher_service_url}/fetcher/ping"
      
      response = HTTParty.get(url)
      
      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error("Failed to wake fetcher service: #{response.code} - #{response.body}")
        { error: "Failed to wake fetcher service: #{response.code}" }
      end
    rescue => e
      Rails.logger.error("Error waking fetcher service: #{e.message}")
      { error: e.message }
    end
    
    private
    
    def fetcher_service_url
      ENV['FETCHER_SERVICE_URL'] || 'http://localhost:3001'
    end
  end
end 
