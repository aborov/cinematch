module Admin
  class FetcherServiceController < Admin::BaseController
    def index
      @fetcher_url = ENV['FETCHER_SERVICE_URL']
      @fetcher_status = fetch_status
    end
    
    def wake
      response = FetcherServiceClient.wake
      
      if response.is_a?(Hash) && !response[:error]
        redirect_to admin_fetcher_service_path, notice: "Fetcher service awakened successfully"
      else
        redirect_to admin_fetcher_service_path, alert: "Failed to wake fetcher service: #{response[:error]}"
      end
    rescue => e
      redirect_to admin_fetcher_service_path, alert: "Error waking fetcher service: #{e.message}"
    end
    
    def test_job
      provider = params[:provider] || 'tmdb'
      batch_size = params[:batch_size] || 5
      
      response = FetcherServiceClient.fetch_movies(provider, batch_size)
      
      if response.is_a?(Hash) && !response[:error]
        redirect_to admin_fetcher_service_path, notice: "Test job started successfully"
      else
        redirect_to admin_fetcher_service_path, alert: "Failed to start test job: #{response[:error]}"
      end
    rescue => e
      redirect_to admin_fetcher_service_path, alert: "Error starting test job: #{e.message}"
    end
    
    private
    
    def fetch_status
      response = FetcherServiceClient.status
      
      if response.is_a?(Hash) && !response[:error]
        response
      else
        { error: "Failed to fetch status: #{response[:error]}" }
      end
    rescue => e
      { error: "Error fetching status: #{e.message}" }
    end
  end
end 
