class FetcherController < ApplicationController
  # Only skip these callbacks if they exist
  skip_before_action :authenticate_user!, if: -> { self.class.instance_methods.include?(:authenticate_user!) || self.class.private_instance_methods.include?(:authenticate_user!) }
  skip_before_action :verify_authenticity_token
  skip_after_action :verify_authorized, if: -> { self.class.instance_methods.include?(:verify_authorized) || self.class.private_instance_methods.include?(:verify_authorized) }
  
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
    render json: { 
      status: "ok", 
      memory_usage: current_memory_usage,
      uptime: process_uptime,
      environment: Rails.env
    }
  end
  
  private
  
  def valid_provider?(provider)
    ['tmdb', 'omdb'].include?(provider)
  end
  
  def current_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024 # Convert KB to MB
  end
  
  def process_uptime
    process_start_time = File.stat("/proc/#{Process.pid}").ctime rescue Time.now - 60
    ((Time.now - process_start_time) / 60).round # in minutes
  end
end 
