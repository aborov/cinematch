# frozen_string_literal: true

# Job to ping the JRuby service to keep it awake on Render free tier
class PingJrubyServiceJob < ApplicationJob
  queue_as :default
  
  # Retry with exponential backoff if the service is not responding
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  
  def perform(*args)
    # Get the JRuby service URL from configuration
    jruby_url = Rails.application.config.jruby_service_url
    
    if !jruby_url.present?
      Rails.logger.warn "JRuby service URL not configured. Check JRUBY_SERVICE_URL environment variable."
      return
    end
    
    # Log the URL we're using
    Rails.logger.info "JRuby service URL: #{jruby_url}"
    
    # Make a request to ping the service
    require 'net/http'
    uri = URI("#{jruby_url}/jruby/ping")
    
    Rails.logger.info "Pinging JRuby service at #{uri}"
    
    begin
      # Use a shorter timeout to avoid long waits
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 5  # seconds
      http.read_timeout = 10 # seconds
      
      response = http.get(uri.path)
      
      if response.code == '200'
        # Parse the response to get service details
        json_response = JSON.parse(response.body)
        
        Rails.logger.info "JRuby service is awake. Engine: #{json_response['engine']}, Version: #{json_response['version']}"
        return true
      else
        Rails.logger.warn "JRuby service ping failed with status code: #{response.code}"
        return false
      end
    rescue => e
      Rails.logger.error "Error pinging JRuby service at #{uri}: #{e.message}"
      Rails.logger.error "This is normal if the JRuby service is not yet deployed or is starting up."
      raise e
    end
  end
  
  # Class method to schedule this job via cron
  # This is an alternative way to schedule the job if the configuration approach doesn't work
  def self.schedule_ping
    if defined?(GoodJob)
      begin
        # Try to schedule using the cron API if available
        if GoodJob.respond_to?(:configure)
          Rails.logger.info "Scheduling #{name} using GoodJob.configure"
          GoodJob.configure do |config|
            config.cron = {
              ping_jruby_service: {
                cron: '*/10 * * * *', # Every 10 minutes
                class: name,
                args: {},
                set: { queue: 'default' }
              }
            } if config.respond_to?(:cron=)
          end
        # Fallback to using Scheduler directly if available
        elsif defined?(GoodJob::Scheduler) && GoodJob::Scheduler.respond_to?(:instance)
          Rails.logger.info "Scheduling #{name} using GoodJob::Scheduler.instance"
          scheduler = GoodJob::Scheduler.instance
          if scheduler.respond_to?(:schedule)
            scheduler.schedule(
              PingJrubyServiceJob,
              cron: '*/10 * * * *', # Every 10 minutes
              kwargs: {}
            )
          end
        else
          Rails.logger.warn "Could not schedule #{name} - GoodJob scheduler API not available"
        end
        
        Rails.logger.info "Scheduled #{name} to run every 10 minutes"
      rescue => e
        Rails.logger.error "Error scheduling #{name}: #{e.message}"
      end
    end
  end
end 
