# frozen_string_literal: true

class FetchContentJob < ApplicationJob
  queue_as :default
  
  # Mark this job to run on the fetcher service
  runs_on_fetcher
  
  # Constants for API providers
  PROVIDERS = %w[tmdb omdb].freeze
  
  # Perform the job
  def perform(provider = 'tmdb', batch_size = 10, options = {})
    log_job_execution(job_id, [provider, batch_size, options])
    
    # If we're not running on the fetcher service, log a warning and notify admins
    if !Rails.env.development? && !options[:allow_mri_execution]
      error_message = "CRITICAL WARNING: FetchContentJob is running on the main app instead of the fetcher service. This may cause memory issues and should be investigated immediately."
      Rails.logger.error error_message
      
      # Notify admins
      begin
        AdminMailer.alert_email(
          title: "Fetcher Job Running on Main App",
          message: error_message,
          details: {
            job_class: self.class.name,
            job_id: job_id,
            args: [provider, batch_size, options],
            ruby_engine: RUBY_ENGINE,
            ruby_version: RUBY_VERSION
          }
        ).deliver_now
        
        # Log fetcher service status
        begin
          status = JobRoutingService.fetcher_service_status
          Rails.logger.error "  Fetcher service status: #{status.inspect}"
          
          # Try to wake the fetcher service
          Rails.logger.error "  Attempting to wake fetcher service..."
          wake_result = JobRoutingService.wake_fetcher_service_with_retries(5)
          Rails.logger.error "  Wake result: #{wake_result.inspect}"
        rescue => e
          Rails.logger.error "  Error checking fetcher service: #{e.message}"
        end
      rescue => e
        Rails.logger.error "Failed to send admin alert: #{e.message}"
      end
      
      # Check if we should allow execution on the main app
      allow_mri_execution = options[:allow_mri_execution] || ENV['ALLOW_FETCHER_JOBS_ON_MAIN'] == 'true'
      
      # Abort if we shouldn't run on the main app
      unless allow_mri_execution
        Rails.logger.error "This job should only run on the fetcher service. Aborting execution."
        return { error: "Job aborted - should run on fetcher service" }
      end
    end
    
    # Validate provider
    unless PROVIDERS.include?(provider)
      Rails.logger.error "Invalid provider: #{provider}. Must be one of: #{PROVIDERS.join(', ')}"
      return { error: "Invalid provider: #{provider}" }
    end
    
    # Validate batch size
    batch_size = batch_size.to_i
    if batch_size <= 0 || batch_size > 100
      Rails.logger.error "Invalid batch size: #{batch_size}. Must be between 1 and 100."
      return { error: "Invalid batch size: #{batch_size}" }
    end
    
    # Log start of job
    Rails.logger.info "Starting FetchContentJob for provider: #{provider}, batch size: #{batch_size}"
    
    # Fetch content based on provider
    result = case provider
             when 'tmdb'
               fetch_from_tmdb(batch_size, options)
             when 'omdb'
               fetch_from_omdb(batch_size, options)
             else
               { error: "Unsupported provider: #{provider}" }
             end
    
    # Log completion
    Rails.logger.info "Completed FetchContentJob for provider: #{provider}, result: #{result.inspect}"
    
    # Return the result
    result
  end
  
  private
  
  # Fetch content from TMDB
  def fetch_from_tmdb(batch_size, options = {})
    Rails.logger.info "Fetching #{batch_size} movies from TMDB"
    
    # Implementation details...
    # This would use the TMDB API to fetch movies
    
    { provider: 'tmdb', count: batch_size, status: 'success' }
  end
  
  # Fetch content from OMDB
  def fetch_from_omdb(batch_size, options = {})
    Rails.logger.info "Fetching #{batch_size} movies from OMDB"
    
    # Implementation details...
    # This would use the OMDB API to fetch movies
    
    { provider: 'omdb', count: batch_size, status: 'success' }
  end
end
