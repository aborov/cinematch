# frozen_string_literal: true

# Service to manage job routing between MRI Ruby and JRuby instances
class JobRoutingService
  # List of job classes that should be routed to JRuby
  JRUBY_JOBS = [
    'FetchContentJob',
    'UpdateAllRecommendationsJob',
    'TestJrubyJob'
  ].freeze
  
  # Queue names for JRuby-specific jobs
  JRUBY_QUEUES = [
    'content_fetching',
    'recommendations',
    'default'
  ].freeze
  
  # Check if a job should be routed to JRuby
  def self.jruby_job?(job_class)
    job_class_name = job_class.is_a?(String) ? job_class : job_class.to_s
    JRUBY_JOBS.include?(job_class_name)
  end
  
  # Check if a queue is for JRuby
  def self.jruby_queue?(queue_name)
    JRUBY_QUEUES.include?(queue_name.to_s)
  end
  
  # Enqueue a job with appropriate routing
  def self.enqueue(job_class, *args)
    # Wake up the JRuby service if this is a JRuby job
    if jruby_job?(job_class)
      Rails.logger.info("Routing job #{job_class} to JRuby service")
      
      # Try to wake up the JRuby service with retries
      wake_success = wake_jruby_service_with_retries(5) # Increased retries
      
      if !wake_success
        Rails.logger.warn("Failed to wake JRuby service after multiple attempts. Job will be enqueued anyway, but may not be processed immediately.")
        
        # Log additional information about the JRuby service
        begin
          status = jruby_service_status
          Rails.logger.warn("JRuby service status: #{status.inspect}")
        rescue => e
          Rails.logger.error("Error checking JRuby service status: #{e.message}")
        end
      end
    end
    
    # Log the job enqueuing
    Rails.logger.info("Enqueuing job #{job_class} with args: #{args.inspect}")
    
    # For JRuby jobs, we still use the standard enqueuing mechanism
    # The job will be picked up by the JRuby service based on its queue
    job = job_class.set(queue: determine_queue(job_class)).perform_later(*args)
    
    # Return the job for tracking
    job
  end
  
  # Determine the appropriate queue for a job
  def self.determine_queue(job_class)
    if job_class.respond_to?(:queue_name)
      job_class.queue_name
    elsif job_class.to_s == 'FetchContentJob'
      'content_fetching'
    elsif job_class.to_s == 'UpdateAllRecommendationsJob'
      'recommendations'
    else
      'default'
    end
  end
  
  # Get the status of JRuby service
  def self.jruby_service_status
    begin
      # Get the JRuby service URL from configuration
      jruby_url = Rails.application.config.jruby_service_url
      return { status: 'unknown', last_heartbeat: nil } unless jruby_url.present?
      
      # Make a request to get the status
      require 'net/http'
      uri = URI("#{jruby_url}/jruby/status")
      
      # Use a longer timeout for status checks
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 30  # seconds
      http.read_timeout = 70  # seconds
      
      response = http.get(uri.path)
      
      if response.code == '200'
        # Parse the response to get service details
        JSON.parse(response.body)
      else
        { status: 'error', error: "Service returned status code: #{response.code}" }
      end
    rescue => e
      Rails.logger.error("Error checking JRuby service status: #{e.message}")
      { status: 'error', error: e.message }
    end
  end
  
  # Wake up the JRuby service with retries
  def self.wake_jruby_service_with_retries(max_attempts = 3)
    attempts = 0
    success = false
    
    while attempts < max_attempts && !success
      attempts += 1
      Rails.logger.info("Attempting to wake JRuby service (attempt #{attempts}/#{max_attempts})")
      
      success = wake_jruby_service
      
      if success
        Rails.logger.info("Successfully woke JRuby service on attempt #{attempts}")
        
        # Record the successful wake-up time
        Rails.cache.write('jruby_service_last_wakeup', Time.now.to_s)
        
        # Verify that the service is actually running JRuby
        begin
          status = jruby_service_status
          if status.is_a?(Hash) && status['engine'] == 'jruby'
            Rails.logger.info("Confirmed JRuby service is running JRuby #{status['version']}")
          else
            Rails.logger.warn("JRuby service responded but may not be running JRuby: #{status.inspect}")
          end
        rescue => e
          Rails.logger.warn("Error verifying JRuby service engine: #{e.message}")
        end
        
        break
      elsif attempts < max_attempts
        # Wait a bit longer between each retry
        sleep_time = attempts * 3  # Increased sleep time
        Rails.logger.info("JRuby service wake attempt #{attempts} failed. Waiting #{sleep_time} seconds before retry...")
        sleep(sleep_time)
      end
    end
    
    success
  end
  
  # Wake up the JRuby service if it's sleeping
  def self.wake_jruby_service
    # This method pings the JRuby service to wake it up if it's sleeping
    # For Render free tier, this is important since the service goes to sleep after inactivity
    begin
      # Get the JRuby service URL from configuration
      jruby_url = Rails.application.config.jruby_service_url
      
      if !jruby_url.present?
        Rails.logger.error("JRuby service URL not configured. Check JRUBY_SERVICE_URL environment variable.")
        return false
      end
      
      # Check if we've recently awakened the service
      if recently_awakened?
        Rails.logger.info("JRuby service was recently awakened, skipping wake-up request")
        return true
      end
      
      Rails.logger.info("Attempting to wake JRuby service at #{jruby_url}")
      
      # Make a request to wake up the service with a timeout
      require 'net/http'
      uri = URI("#{jruby_url}/jruby/ping")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 60  # seconds (increased from 30)
      http.read_timeout = 120  # seconds (increased from 60)
      
      response = http.get(uri.path)
      
      # Return true if the service responded successfully
      success = response.code == '200'
      
      if success
        begin
          json_response = JSON.parse(response.body)
          Rails.logger.info("JRuby service wake successful. Engine: #{json_response['engine']}, Version: #{json_response['version']}")
          
          # Verify that it's actually JRuby
          if json_response['engine'] != 'jruby'
            Rails.logger.warn("Service responded but is not running JRuby! Engine: #{json_response['engine']}")
          end
        rescue JSON::ParserError
          Rails.logger.info("JRuby service wake successful, but response was not valid JSON")
        end
      else
        Rails.logger.warn("JRuby service wake attempt failed with status code: #{response.code}")
      end
      
      success
    rescue Net::OpenTimeout => e
      Rails.logger.error("Timeout opening connection to JRuby service: #{e.message}")
      Rails.logger.error("This is normal if the service is sleeping and starting up. Will retry.")
      false
    rescue Net::ReadTimeout => e
      Rails.logger.error("Timeout reading from JRuby service: #{e.message}")
      Rails.logger.error("This may indicate that the service is busy or starting up. Will retry.")
      false
    rescue => e
      Rails.logger.error("Error waking JRuby service: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end
  
  # Check if the JRuby service was recently awakened
  def self.recently_awakened?
    last_wakeup = Rails.cache.read('jruby_service_last_wakeup')
    return false if last_wakeup.nil?
    
    # Parse the timestamp
    begin
      last_wakeup_time = Time.parse(last_wakeup)
      time_since_wakeup = Time.now - last_wakeup_time
      
      # If it's been less than 30 seconds since the last wake-up, consider it recently awakened
      if time_since_wakeup < 30.seconds
        Rails.logger.info("JRuby service was awakened #{time_since_wakeup.round(1)} seconds ago")
        return true
      end
    rescue => e
      Rails.logger.error("Error parsing last wakeup time: #{e.message}")
    end
    
    false
  end
  
  # Check if there are any pending jobs in JRuby queues
  def self.pending_jruby_jobs?
    begin
      JRUBY_QUEUES.each do |queue|
        pending_count = GoodJob::Job.where(queue_name: queue, performed_at: nil).count
        return true if pending_count > 0
      end
      false
    rescue => e
      Rails.logger.error("Error checking for pending JRuby jobs: #{e.message}")
      false
    end
  end
end 
