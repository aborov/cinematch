class JobRunnerService
  class << self
    def run_job(job_class, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating job #{job_class} to job runner service"
      
      begin
        response = HTTParty.post(
          "#{job_runner_url}/api/job_runner/run_job",
          body: {
            job_class: job_class,
            args: args,
            secret: job_runner_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        
        if response.success?
          Rails.logger.info "[JobRunnerService] Successfully delegated job #{job_class} to job runner. Job ID: #{response['job_id']}"
          return response['job_id']
        else
          Rails.logger.error "[JobRunnerService] Failed to delegate job #{job_class} to job runner. Status: #{response.code}, Error: #{response.body}"
          return false
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error delegating job #{job_class} to job runner: #{e.message}"
        return false
      end
    end
    
    def run_specific_job(job_class, method_name, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating specific job #{job_class}##{method_name} to job runner service"
      
      begin
        response = HTTParty.post(
          "#{job_runner_url}/api/job_runner/run_specific_job",
          body: {
            job_class: job_class,
            method_name: method_name,
            args: args,
            secret: job_runner_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        
        if response.success?
          Rails.logger.info "[JobRunnerService] Successfully delegated specific job #{job_class}##{method_name} to job runner. Job ID: #{response['job_id']}"
          return response['job_id']
        else
          Rails.logger.error "[JobRunnerService] Failed to delegate specific job #{job_class}##{method_name} to job runner. Status: #{response.code}, Error: #{response.body}"
          return false
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error delegating specific job #{job_class}##{method_name} to job runner: #{e.message}"
        return false
      end
    end
    
    def check_job_status(job_id)
      return nil unless job_runner_enabled?
      
      begin
        response = HTTParty.get(
          "#{job_runner_url}/api/job_runner/job_status/#{job_id}",
          query: { secret: job_runner_secret },
          headers: { 'Content-Type' => 'application/json' }
        )
        
        if response.success?
          return response.parsed_response
        else
          Rails.logger.error "[JobRunnerService] Failed to check job status for job ID #{job_id}. Status: #{response.code}, Error: #{response.body}"
          return nil
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error checking job status for job ID #{job_id}: #{e.message}"
        return nil
      end
    end
    
    def wake_up_job_runner
      return true if Rails.env.development? || ENV['JOB_RUNNER_ONLY'] == 'true'
      
      begin
        response = HTTParty.get("#{job_runner_url}/health_check")
        
        if response.success?
          Rails.logger.info "[JobRunnerService] Job runner is awake and healthy"
          return true
        else
          Rails.logger.error "[JobRunnerService] Job runner health check failed. Status: #{response.code}, Error: #{response.body}"
          return false
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Error waking up job runner: #{e.message}"
        return false
      end
    end
    
    private
    
    def job_runner_enabled?
      return false if Rails.env.development? && ENV['USE_JOB_RUNNER'] != 'true'
      return false if ENV['JOB_RUNNER_ONLY'] == 'true' # Don't delegate if we are the job runner
      
      true
    end
    
    def job_runner_url
      ENV.fetch('JOB_RUNNER_URL', 'https://cinematch-job-runner.onrender.com')
    end
    
    def job_runner_secret
      # Use the first 16 characters of the SECRET_KEY_BASE as a shared secret
      ENV['SECRET_KEY_BASE'].to_s[0..15]
    end
  end
end 
