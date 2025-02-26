# frozen_string_literal: true

# Job to ping the JRuby service to keep it awake on Render free tier
class PingJrubyServiceJob < ApplicationJob
  queue_as :default
  
  # Retry with exponential backoff if the service is not responding
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(*args)
    # Get the JRuby service URL from configuration
    jruby_url = Rails.application.config.jruby_service_url
    return unless jruby_url.present?
    
    # Make a request to ping the service
    require 'net/http'
    uri = URI("#{jruby_url}/jruby/ping")
    
    Rails.logger.info "Pinging JRuby service at #{uri}"
    
    begin
      response = Net::HTTP.get_response(uri)
      
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
      Rails.logger.error "Error pinging JRuby service: #{e.message}"
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
