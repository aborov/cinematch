require 'httparty'

class FetcherServiceClient
  class << self
    def fetch_movies(provider, batch_size = nil)
      begin
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
      rescue NameError => e
        if e.message.include?('HTTParty')
          Rails.logger.error("HTTParty gem not loaded: #{e.message}")
          Rails.logger.error("Attempting to load HTTParty...")
          begin
            require 'httparty'
            retry
          rescue LoadError => le
            Rails.logger.error("Failed to load HTTParty: #{le.message}")
            { error: "Failed to load HTTParty: #{le.message}" }
          end
        else
          Rails.logger.error("Unexpected error: #{e.message}")
          { error: "Unexpected error: #{e.message}" }
        end
      rescue => e
        Rails.logger.error("Error in fetch_movies: #{e.message}")
        { error: "Error in fetch_movies: #{e.message}" }
      end
    end
    
    def status
      begin
        url = "#{fetcher_service_url}/fetcher/ping"
        response = HTTParty.get(url, timeout: 5)
        
        if response.success?
          status_data = JSON.parse(response.body)
          { status: "ok", data: status_data }
        else
          Rails.logger.error("Failed to get fetcher service status: #{response.code} - #{response.body}")
          { status: "error", error: "Failed to get fetcher service status: #{response.code}" }
        end
      rescue NameError => e
        if e.message.include?('HTTParty')
          Rails.logger.error("HTTParty gem not loaded: #{e.message}")
          Rails.logger.error("Attempting to load HTTParty...")
          begin
            require 'httparty'
            retry
          rescue LoadError => le
            Rails.logger.error("Failed to load HTTParty: #{le.message}")
            { status: "error", error: "Failed to load HTTParty: #{le.message}" }
          end
        else
          Rails.logger.error("Unexpected error: #{e.message}")
          { status: "error", error: "Unexpected error: #{e.message}" }
        end
      rescue => e
        Rails.logger.error("Error getting fetcher service status: #{e.message}")
        { status: "error", error: "Error getting fetcher service status: #{e.message}" }
      end
    end
    
    def wake
      begin
        url = "#{fetcher_service_url}/fetcher/ping"
        response = HTTParty.get(url)
        
        if response.success?
          JSON.parse(response.body)
        else
          Rails.logger.error("Failed to wake fetcher service: #{response.code} - #{response.body}")
          { error: "Failed to wake fetcher service: #{response.code}" }
        end
      rescue NameError => e
        if e.message.include?('HTTParty')
          Rails.logger.error("HTTParty gem not loaded: #{e.message}")
          Rails.logger.error("Attempting to load HTTParty...")
          begin
            require 'httparty'
            retry
          rescue LoadError => le
            Rails.logger.error("Failed to load HTTParty: #{le.message}")
            { error: "Failed to load HTTParty: #{le.message}" }
          end
        else
          Rails.logger.error("Unexpected error: #{e.message}")
          { error: "Unexpected error: #{e.message}" }
        end
      rescue => e
        Rails.logger.error("Error waking fetcher service: #{e.message}")
        { error: "Error waking fetcher service: #{e.message}" }
      end
    end
    
    private
    
    def fetcher_service_url
      ENV['FETCHER_SERVICE_URL'] || 'http://localhost:3001'
    end
  end
end 
