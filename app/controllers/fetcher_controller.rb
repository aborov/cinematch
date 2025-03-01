class FetcherController < ApplicationController
  skip_before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!) }
  skip_before_action :verify_authenticity_token
  skip_after_action :verify_authorized, if: -> { respond_to?(:verify_authorized) }
  
  # Health check endpoint
  def ping
    render json: { status: "ok", service: "fetcher" }
  end
  
  # Trigger a fetch job
  def fetch
    # Parse parameters
    provider = params[:provider]
    batch_size = (params[:batch_size] || ENV.fetch('BATCH_SIZE', 20)).to_i
    
    # Validate parameters
    unless valid_provider?(provider)
      return render json: { error: "Invalid provider" }, status: :bad_request
    end
    
    # Start the fetch job in a background thread to avoid timeout
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          case provider
          when 'tmdb'
            result = TmdbService.fetch_movies(batch_size)
          when 'omdb'
            result = OmdbService.fetch_movies(batch_size)
          end
          
          # Log the result
          Rails.logger.info("Fetcher job completed: #{result.inspect}")
          
          # Update the last run timestamp
          FetcherStatus.update_last_run(provider)
        rescue => e
          Rails.logger.error("Fetcher job failed: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end
    end
    
    render json: { status: "fetch_started", provider: provider, batch_size: batch_size }
  end
  
  # Get status of the fetcher service
  def status
    statuses = FetcherStatus.all.map do |status|
      {
        provider: status.provider,
        last_run: status.last_run,
        status: status.status,
        movies_fetched: status.movies_fetched
      }
    end
    
    render json: { 
      status: "ok", 
      memory_usage: current_memory_usage,
      providers: statuses
    }
  end
  
  private
  
  def valid_provider?(provider)
    ['tmdb', 'omdb'].include?(provider)
  end
  
  def current_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024 # Convert KB to MB
  end
end 
