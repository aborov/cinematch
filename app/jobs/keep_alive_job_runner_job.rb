class KeepAliveJobRunnerJob < ApplicationJob
  queue_as :default
  
  # How often to ping the job runner (in seconds)
  PING_INTERVAL = 4.minutes
  
  # Maximum number of pings before giving up (approximately 2 hours)
  MAX_PINGS = 30
  
  def perform(job_id, ping_count = 0)
    Rails.logger.info "[KeepAliveJobRunnerJob] Checking status of job #{job_id} (ping #{ping_count}/#{MAX_PINGS})"
    
    # Stop pinging if we've reached the maximum number of pings
    if ping_count >= MAX_PINGS
      Rails.logger.info "[KeepAliveJobRunnerJob] Reached maximum number of pings (#{MAX_PINGS}) for job #{job_id}, stopping keep-alive"
      return
    end
    
    # Check if the job is still running
    if JobRunnerService.job_running?(job_id)
      # Send a keep-alive ping to the job runner
      JobRunnerService.keep_alive
      
      # Schedule the next ping
      Rails.logger.info "[KeepAliveJobRunnerJob] Job #{job_id} is still running, scheduling next ping in #{PING_INTERVAL} seconds"
      KeepAliveJobRunnerJob.set(wait: PING_INTERVAL).perform_later(job_id, ping_count + 1)
    else
      Rails.logger.info "[KeepAliveJobRunnerJob] Job #{job_id} is no longer running, stopping keep-alive"
    end
  end
end 
