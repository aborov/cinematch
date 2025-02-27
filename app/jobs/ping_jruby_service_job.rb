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
    
    # Check if there are any pending jobs in JRuby queues
    pending_jobs = check_jruby_queues
    
    # Only ping if there are pending jobs or if it's been a long time since last ping
    if pending_jobs > 0 || should_ping_anyway?
      # Log the URL we're using
      Rails.logger.info "JRuby service URL: #{jruby_url}"
      
      # Make a request to ping the service
      require 'net/http'
      uri = URI("#{jruby_url}/jruby/ping")
      
      Rails.logger.info "Pinging JRuby service at #{uri} (#{pending_jobs} pending jobs)"
      
      begin
        # Use a shorter timeout to avoid long waits
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 15  # seconds (increased from 5)
        http.read_timeout = 30  # seconds (increased from 10)
        
        response = http.get(uri.path)
        
        if response.code == '200'
          # Parse the response to get service details
          json_response = JSON.parse(response.body)
          
          Rails.logger.info "JRuby service is awake. Engine: #{json_response['engine']}, Version: #{json_response['version']}"
          
          # Update the last ping timestamp
          update_last_ping_timestamp
          
          return true
        else
          Rails.logger.warn "JRuby service ping failed with status code: #{response.code}"
          return false
        end
      rescue Net::OpenTimeout => e
        Rails.logger.error "Timeout opening connection to JRuby service at #{uri}: #{e.message}"
        Rails.logger.error "This may indicate that the JRuby service is starting up or is not deployed."
        # Don't raise the exception for open timeouts, as this is expected when the service is sleeping
        return false
      rescue Net::ReadTimeout => e
        Rails.logger.error "Timeout reading from JRuby service at #{uri}: #{e.message}"
        Rails.logger.error "This may indicate that the JRuby service is busy or overloaded."
        # Don't raise the exception for read timeouts, as this is expected when the service is busy
        return false
      rescue => e
        Rails.logger.error "Error pinging JRuby service at #{uri}: #{e.message}"
        Rails.logger.error "This is normal if the JRuby service is not yet deployed or is starting up."
        raise e
      end
    else
      Rails.logger.info "Skipping JRuby service ping - no pending jobs and last ping was recent"
      return true
    end
  end
  
  # Check if there are any jobs in the JRuby queues
  def check_jruby_queues
    begin
      # Get the queues that should be processed by JRuby
      jruby_queues = JobRoutingService::JRUBY_QUEUES
      
      # Count pending jobs across all JRuby queues
      pending_count = 0
      
      # Check each queue for pending jobs
      jruby_queues.each do |queue|
        queue_pending_count = GoodJob::Job.where(queue_name: queue, performed_at: nil).count
        pending_count += queue_pending_count
        
        if queue_pending_count > 0
          Rails.logger.info "Found #{queue_pending_count} pending jobs in JRuby queue '#{queue}'"
        end
      end
      
      # If there are pending jobs, wake up the JRuby service
      if pending_count > 0
        Rails.logger.info "Found a total of #{pending_count} pending jobs across all JRuby queues"
        JobRoutingService.wake_jruby_service_with_retries(5)
      end
      
      return pending_count
    rescue => e
      Rails.logger.error "Error checking JRuby queues: #{e.message}"
      return 0
    end
  end
  
  # Check if we should ping anyway (e.g., it's been a long time since last ping)
  def should_ping_anyway?
    # Get the last ping timestamp
    last_ping = Rails.cache.read('jruby_service_last_ping')
    
    if last_ping.nil?
      # If we've never pinged before, we should ping
      Rails.logger.info "No record of previous JRuby service ping, will ping"
      return true
    end
    
    # Calculate time since last ping
    time_since_last_ping = Time.now - Time.parse(last_ping)
    
    # If it's been more than 30 minutes, ping anyway to keep the service warm
    # This is especially important for free tier services that sleep after inactivity
    should_ping = time_since_last_ping > 30.minutes
    
    if should_ping
      Rails.logger.info "Last JRuby service ping was #{(time_since_last_ping / 60).round} minutes ago, will ping to keep warm"
    end
    
    return should_ping
  end
  
  # Update the timestamp of the last ping
  def update_last_ping_timestamp
    Rails.cache.write('jruby_service_last_ping', Time.now.to_s)
  end
  
  # Class method to schedule this job via cron
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
