class KeepAliveJobRunnerJob < ApplicationJob
  queue_as :default
  
  # How often to ping the job runner (in seconds)
  PING_INTERVAL = 4.minutes
  
  # Default maximum number of pings (approximately 8 hours)
  DEFAULT_MAX_PINGS = 120
  
  # Job-specific maximum pings
  JOB_SPECIFIC_MAX_PINGS = {
    'FetchContentJob' => 150, # ~10 hours (to be safe)
    'UpdateAllRecommendationsJob' => 60, # ~4 hours
    'FillMissingDetailsJob' => 90 # ~6 hours
  }
  
  def perform(job_id, ping_count = 0, job_class = nil)
    # Get the maximum pings for this job type
    max_pings = get_max_pings(job_class)
    
    Rails.logger.info "[KeepAliveJobRunnerJob] Checking status of job #{job_id} (ping #{ping_count}/#{max_pings})"
    
    # Stop pinging if we've reached the maximum number of pings
    if ping_count >= max_pings
      Rails.logger.info "[KeepAliveJobRunnerJob] Reached maximum number of pings (#{max_pings}) for job #{job_id}, stopping keep-alive"
      return
    end
    
    # Check if the job is still running
    if JobRunnerService.job_running?(job_id)
      # Send a keep-alive ping to the job runner
      JobRunnerService.keep_alive
      
      # Schedule the next ping
      Rails.logger.info "[KeepAliveJobRunnerJob] Job #{job_id} is still running, scheduling next ping in #{PING_INTERVAL} seconds"
      KeepAliveJobRunnerJob.set(wait: PING_INTERVAL).perform_later(job_id, ping_count + 1, job_class)
    else
      Rails.logger.info "[KeepAliveJobRunnerJob] Job #{job_id} is no longer running, stopping keep-alive"
    end
  end
  
  private
  
  def get_max_pings(job_class)
    return DEFAULT_MAX_PINGS unless job_class.present?
    JOB_SPECIFIC_MAX_PINGS[job_class] || DEFAULT_MAX_PINGS
  end
end 
