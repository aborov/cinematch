class JobRunnerService
  class << self
    def wake_up
      return true unless ENV['JOB_RUNNER_URL'].present?
      
      Rails.logger.info "[JobRunnerService] Waking up job runner at #{ENV['JOB_RUNNER_URL']}"
      start_time = Time.current
      
      begin
        response = HTTP.timeout(60).get("#{ENV['JOB_RUNNER_URL']}/health_check")
        
        if response.status.success?
          duration = Time.current - start_time
          Rails.logger.info "[JobRunnerService] Job runner is awake! Response time: #{duration.round(2)}s"
          return true
        else
          Rails.logger.error "[JobRunnerService] Failed to wake up job runner. Status: #{response.status}"
          return false
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error waking up job runner: #{e.message}"
        return false
      end
    end
    
    def run_job(job_class, args = {})
      return false unless ENV['JOB_RUNNER_URL'].present?
      
      # First wake up the job runner
      unless wake_up
        Rails.logger.error "[JobRunnerService] Cannot run job #{job_class} because job runner is not available"
        return false
      end
      
      Rails.logger.info "[JobRunnerService] Requesting job runner to run #{job_class} with args: #{args.inspect}"
      
      begin
        response = HTTP.timeout(30).post(
          "#{ENV['JOB_RUNNER_URL']}/api/run_job",
          json: {
            job_class: job_class,
            args: args,
            secret: ENV['SECRET_KEY_BASE'].to_s[0..15] # Use part of the secret key as a simple auth token
          }
        )
        
        if response.status.success?
          result = JSON.parse(response.body.to_s)
          Rails.logger.info "[JobRunnerService] Job #{job_class} scheduled successfully. Job ID: #{result['job_id']}"
          return result['job_id']
        else
          Rails.logger.error "[JobRunnerService] Failed to schedule job #{job_class}. Status: #{response.status}"
          return false
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error scheduling job #{job_class}: #{e.message}"
        return false
      end
    end
    
    def job_status(job_id)
      return nil unless ENV['JOB_RUNNER_URL'].present?
      
      begin
        response = HTTP.timeout(10).get(
          "#{ENV['JOB_RUNNER_URL']}/api/job_status",
          params: {
            job_id: job_id,
            secret: ENV['SECRET_KEY_BASE'].to_s[0..15]
          }
        )
        
        if response.status.success?
          return JSON.parse(response.body.to_s)
        else
          Rails.logger.error "[JobRunnerService] Failed to get job status for #{job_id}. Status: #{response.status}"
          return nil
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error getting job status for #{job_id}: #{e.message}"
        return nil
      end
    end
  end
end 
