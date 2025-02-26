# frozen_string_literal: true

# Service to manage job routing between MRI Ruby and JRuby instances
class JobRoutingService
  # List of job classes that should be routed to JRuby
  JRUBY_JOBS = [
    'FetchContentJob',
    'UpdateAllRecommendationsJob'
  ].freeze
  
  # Queue names for JRuby-specific jobs
  JRUBY_QUEUES = [
    'content_fetching',
    'recommendations'
  ].freeze
  
  # Check if a job should be routed to JRuby
  def self.jruby_job?(job_class)
    JRUBY_JOBS.include?(job_class.to_s)
  end
  
  # Check if a queue is for JRuby
  def self.jruby_queue?(queue_name)
    JRUBY_QUEUES.include?(queue_name.to_s)
  end
  
  # Enqueue a job with appropriate routing
  def self.enqueue(job_class, *args)
    # Wake up the JRuby service if this is a JRuby job
    wake_jruby_service if jruby_job?(job_class)
    
    # Add JRuby-specific metadata if needed
    if jruby_job?(job_class)
      # Add metadata to indicate this job should be picked up by JRuby
      job = job_class.set(queue: job_class.queue_name)
      
      # Perform the job later
      job.perform_later(*args)
    else
      # Use the standard enqueue for non-JRuby jobs
      job_class.perform_later(*args)
    end
  end
  
  # Schedule a job to run at a specific time
  def self.schedule(job_class, scheduled_at, options = {})
    # Wake up the JRuby service if this is a JRuby job
    wake_jruby_service if jruby_job?(job_class)
    
    # Add JRuby-specific metadata if needed
    if jruby_job?(job_class)
      # Add metadata to indicate this job should be picked up by JRuby
      job = job_class.set(wait_until: scheduled_at, queue: job_class.queue_name)
      
      # Perform the job later
      job.perform_later(options)
    else
      # Use the standard scheduling for non-JRuby jobs
      job_class.set(wait_until: scheduled_at).perform_later(options)
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
      response = Net::HTTP.get_response(uri)
      
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
  
  # Wake up the JRuby service if it's sleeping
  def self.wake_jruby_service
    # This method pings the JRuby service to wake it up if it's sleeping
    # For Render free tier, this is important since the service goes to sleep after inactivity
    begin
      # Get the JRuby service URL from configuration
      jruby_url = Rails.application.config.jruby_service_url
      return false unless jruby_url.present?
      
      Rails.logger.info("Attempting to wake JRuby service at #{jruby_url}")
      
      # Make a request to wake up the service
      require 'net/http'
      uri = URI("#{jruby_url}/jruby/ping")
      response = Net::HTTP.get_response(uri)
      
      # Return true if the service responded successfully
      success = response.code == '200'
      Rails.logger.info("JRuby service wake attempt #{success ? 'succeeded' : 'failed'}")
      success
    rescue => e
      Rails.logger.error("Error waking JRuby service: #{e.message}")
      false
    end
  end
end 
