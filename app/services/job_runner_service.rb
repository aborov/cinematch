require 'httparty'

class JobRunnerService
  class << self
    def run_job(job_class, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating job #{job_class} to job runner service with args: #{args.inspect}"
      
      begin
        # First ensure the job runner is awake
        unless wake_up_job_runner
          Rails.logger.error "[JobRunnerService] Job runner is not responding. Cannot delegate job #{job_class}"
          return false
        end
        
        # Ensure args is a regular hash, not an ActionController::Parameters object
        args_hash = args.respond_to?(:to_unsafe_h) ? args.to_unsafe_h : args
        
        response = HTTParty.post(
          "#{job_runner_url}/api/job_runner/run_job",
          body: {
            job_class: job_class,
            args: args_hash,
            secret: job_runner_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' },
          timeout: 10 # Add a timeout to prevent hanging requests
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
        Rails.logger.error e.backtrace.join("\n")
        return false
      end
    end
    
    def run_specific_job(job_class, method_name, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating specific job #{job_class}##{method_name} to job runner service with args: #{args.inspect}"
      
      begin
        # First ensure the job runner is awake
        unless wake_up_job_runner
          Rails.logger.error "[JobRunnerService] Job runner is not responding. Cannot delegate job #{job_class}##{method_name}"
          return false
        end
        
        # Ensure args is a regular hash, not an ActionController::Parameters object
        args_hash = args.respond_to?(:to_unsafe_h) ? args.to_unsafe_h : args
        
        response = HTTParty.post(
          "#{job_runner_url}/api/job_runner/run_specific_job",
          body: {
            job_class: job_class,
            method_name: method_name,
            args: args_hash,
            secret: job_runner_secret
          }.to_json,
          headers: { 'Content-Type' => 'application/json' },
          timeout: 10 # Add a timeout to prevent hanging requests
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
        Rails.logger.error e.backtrace.join("\n")
        return false
      end
    end
    
    def check_job_status(job_id)
      return nil unless job_runner_enabled?
      
      begin
        response = HTTParty.get(
          "#{job_runner_url}/api/job_runner/job_status/#{job_id}",
          query: { secret: job_runner_secret },
          headers: { 'Content-Type' => 'application/json' },
          timeout: 5 # Add a timeout to prevent hanging requests
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
        Rails.logger.info "[JobRunnerService] Attempting to wake up job runner at #{job_runner_url}/health_check"
        response = HTTParty.get(
          "#{job_runner_url}/health_check",
          timeout: 10 # Add a timeout to prevent hanging requests
        )
        
        if response.success?
          Rails.logger.info "[JobRunnerService] Job runner is awake and healthy: #{response.body}"
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
      # Don't delegate if we are in development and not explicitly using job runner
      if Rails.env.development? && ENV['USE_JOB_RUNNER'] != 'true'
        Rails.logger.info "[JobRunnerService] Job runner disabled in development environment"
        return false
      end
      
      # Don't delegate if we are the job runner
      if ENV['JOB_RUNNER_ONLY'] == 'true'
        Rails.logger.info "[JobRunnerService] We are the job runner, not delegating"
        return false
      end
      
      # In production, always delegate unless we're the job runner
      Rails.logger.info "[JobRunnerService] Job runner enabled, will delegate jobs"
      true
    end
    
    def job_runner_url
      url = ENV.fetch('JOB_RUNNER_URL', 'https://cinematch-job-runner.onrender.com')
      Rails.logger.info "[JobRunnerService] Using job runner URL: #{url}"
      url
    end
    
    def job_runner_secret
      # Use a dedicated shared secret for job runner authentication
      # Fall back to SECRET_KEY_BASE if JOB_RUNNER_SECRET is not set
      secret = ENV['JOB_RUNNER_SECRET'] || ENV['SECRET_KEY_BASE'].to_s[0..15]
      Rails.logger.info "[JobRunnerService] Using job runner secret: #{secret[0..3]}..." if Rails.env.development?
      secret
    end
  end
end 
