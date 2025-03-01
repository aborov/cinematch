module Admin
  class FetcherServiceController < Admin::ApplicationController
    def index
      @fetcher_url = ENV['FETCHER_SERVICE_URL']
      @fetcher_status = fetch_status
    end
    
    def wake
      response = HTTParty.get("#{ENV['FETCHER_SERVICE_URL']}/fetcher/ping")
      
      if response.success?
        redirect_to admin_fetcher_service_path, notice: "Fetcher service awakened successfully"
      else
        redirect_to admin_fetcher_service_path, alert: "Failed to wake fetcher service: #{response.code}"
      end
    rescue => e
      redirect_to admin_fetcher_service_path, alert: "Error waking fetcher service: #{e.message}"
    end
    
    def test_job
      provider = params[:provider] || 'tmdb'
      batch_size = params[:batch_size] || 5
      
      response = HTTParty.post(
        "#{ENV['FETCHER_SERVICE_URL']}/fetcher/fetch",
        body: { provider: provider, batch_size: batch_size }
      )
      
      if response.success?
        redirect_to admin_fetcher_service_path, notice: "Test job started successfully"
      else
        redirect_to admin_fetcher_service_path, alert: "Failed to start test job: #{response.code}"
      end
    rescue => e
      redirect_to admin_fetcher_service_path, alert: "Error starting test job: #{e.message}"
    end
    
    private
    
    def fetch_status
      response = HTTParty.get("#{ENV['FETCHER_SERVICE_URL']}/fetcher/status")
      
      if response.success?
        JSON.parse(response.body)
      else
        { error: "Failed to fetch status: #{response.code}" }
      end
    rescue => e
      { error: "Error fetching status: #{e.message}" }
    end
  end
end 
