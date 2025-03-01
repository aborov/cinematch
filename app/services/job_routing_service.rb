# frozen_string_literal: true

# Service to manage job routing between main app and fetcher service
class JobRoutingService
  # List of job classes that should be routed to the fetcher service
  FETCHER_JOBS = [
    'FetchContentJob',
    'UpdateAllRecommendationsJob',
    'TestFetcherJob'
  ].freeze
  
  # Queue names for fetcher-specific jobs
  FETCHER_QUEUES = [
    'content_fetching',
    'recommendations',
    'default'
  ].freeze
  
  # Check if a job should be routed to the fetcher service
  def self.fetcher_job?(job_class)
    job_class_name = job_class.is_a?(String) ? job_class : job_class.to_s
    FETCHER_JOBS.include?(job_class_name)
  end
  
  # Check if a queue is for the fetcher service
  def self.fetcher_queue?(queue_name)
    FETCHER_QUEUES.include?(queue_name.to_s)
  end
  
  # Enqueue a job with appropriate routing
  def self.enqueue(job_class, *args)
    # For fetcher jobs, route to the fetcher service
    if fetcher_job?(job_class)
      Rails.logger.info("Routing job #{job_class} to fetcher service")
      
      # Try to wake up the fetcher service with retries
      wake_success = wake_fetcher_service_with_retries(5)
      
      if !wake_success
        Rails.logger.warn("Failed to wake fetcher service after multiple attempts. Job will be enqueued anyway, but may not be processed immediately.")
        
        # Log additional information about the fetcher service
        begin
          status = FetcherServiceClient.status
          Rails.logger.warn("Fetcher service status: #{status.inspect}")
        rescue => e
          Rails.logger.error("Error checking fetcher service status: #{e.message}")
        end
      end
      
      # For fetcher jobs, we need to call the fetcher service API
      if job_class.to_s == 'FetchContentJob'
        provider = args.first || 'tmdb'
        batch_size = args.second || ENV.fetch('BATCH_SIZE', 20).to_i
        
        result = FetcherServiceClient.fetch_movies(provider, batch_size)
        Rails.logger.info("Fetcher service job started: #{result.inspect}")
        
        # Return a mock job for compatibility
        return OpenStruct.new(
          id: SecureRandom.uuid,
          job_class: job_class.to_s,
          queue_name: determine_queue(job_class),
          arguments: args,
          created_at: Time.current
        )
      end
    end
    
    # Log the job enqueuing
    Rails.logger.info("Enqueuing job #{job_class} with args: #{args.inspect}")
    
    # For non-fetcher jobs, use the standard enqueuing mechanism
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
  
  # Wake up the fetcher service with retries
  def self.wake_fetcher_service_with_retries(max_attempts = 3)
    attempts = 0
    success = false
    
    while attempts < max_attempts && !success
      attempts += 1
      Rails.logger.info("Attempting to wake fetcher service (attempt #{attempts}/#{max_attempts})")
      
      success = wake_fetcher_service
      
      if success
        Rails.logger.info("Successfully woke fetcher service on attempt #{attempts}")
        
        # Record the successful wake-up time
        Rails.cache.write('fetcher_service_last_wakeup', Time.now.to_s)
        break
      elsif attempts < max_attempts
        # Wait a bit longer between each retry
        sleep_time = attempts * 3
        Rails.logger.info("Fetcher service wake attempt #{attempts} failed. Waiting #{sleep_time} seconds before retry...")
        sleep(sleep_time)
      end
    end
    
    success
  end
  
  # Wake up the fetcher service if it's sleeping
  def self.wake_fetcher_service
    # This method pings the fetcher service to wake it up if it's sleeping
    # For Render free tier, this is important since the service goes to sleep after inactivity
    begin
      if !ENV['FETCHER_SERVICE_URL'].present?
        Rails.logger.error("Fetcher service URL not configured. Check FETCHER_SERVICE_URL environment variable.")
        return false
      end
      
      # Check if we've recently awakened the service
      if recently_awakened?
        Rails.logger.info("Fetcher service was recently awakened, skipping wake-up request")
        return true
      end
      
      Rails.logger.info("Attempting to wake fetcher service")
      
      # Use the FetcherServiceClient to wake the service
      result = FetcherServiceClient.wake
      
      success = result.is_a?(Hash) && !result[:error]
      
      if success
        Rails.logger.info("Fetcher service wake successful: #{result.inspect}")
      else
        Rails.logger.warn("Fetcher service wake attempt failed: #{result.inspect}")
      end
      
      success
    rescue => e
      Rails.logger.error("Error waking fetcher service: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end
  
  # Check if the fetcher service was recently awakened
  def self.recently_awakened?
    last_wakeup = Rails.cache.read('fetcher_service_last_wakeup')
    return false if last_wakeup.nil?
    
    # Parse the timestamp
    begin
      last_wakeup_time = Time.parse(last_wakeup)
      time_since_wakeup = Time.now - last_wakeup_time
      
      # If it's been less than 30 seconds since the last wake-up, consider it recently awakened
      if time_since_wakeup < 30.seconds
        Rails.logger.info("Fetcher service was awakened #{time_since_wakeup.round(1)} seconds ago")
        return true
      end
    rescue => e
      Rails.logger.error("Error parsing last wakeup time: #{e.message}")
    end
    
    false
  end
  
  # Check if there are any pending jobs in fetcher queues
  def self.pending_fetcher_jobs?
    begin
      FETCHER_QUEUES.each do |queue|
        pending_count = GoodJob::Job.where(queue_name: queue, performed_at: nil).count
        return true if pending_count > 0
      end
      false
    rescue => e
      Rails.logger.error("Error checking for pending fetcher jobs: #{e.message}")
      false
    end
  end
end 
