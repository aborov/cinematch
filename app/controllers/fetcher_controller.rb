class FetcherController < ApplicationController
  # Skip authentication and CSRF protection for API endpoints
  skip_before_action :verify_authenticity_token
  
  # Only skip these callbacks if they exist
  if defined?(Devise)
    skip_before_action :authenticate_user!, raise: false
  end
  
  # Skip Pundit authorization if it's being used
  if defined?(Pundit)
    skip_after_action :verify_authorized, raise: false
  end
  
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
    job_id = nil
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          # Use FetchContentJob instead of directly calling service classes
          job = FetchContentJob.perform_later(provider, batch_size, { allow_mri_execution: true })
          job_id = job.job_id
          
          # Log the job ID
          Rails.logger.info("Fetcher job started: #{job_id}")
        rescue => e
          Rails.logger.error("Failed to start fetcher job: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end
    end
    
    # Return success response with job ID if available
    render json: { status: "ok", message: "Fetch job started", job_id: job_id }
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
    FetchContentJob::PROVIDERS.include?(provider)
  end
  
  def current_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024 # Convert KB to MB
  end
  
  def process_uptime
    process_start_time = File.stat("/proc/#{Process.pid}").ctime rescue Time.now - 60
    ((Time.now - process_start_time) / 60).round # in minutes
  end
end 
