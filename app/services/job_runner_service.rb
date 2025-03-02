require 'httparty'

class JobRunnerService
  class << self
    def run_job(job_class, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating job #{job_class} to job runner service with args: #{args.inspect}"
      
      begin
        # First ensure the job runner is awake with retries
        unless wake_up_job_runner(max_retries: 3)
          Rails.logger.error "[JobRunnerService] Job runner is not responding after retries. Cannot delegate job #{job_class}"
          return false
        end
        
        # Ensure args is a regular hash, not an ActionController::Parameters object
        args_hash = args.respond_to?(:to_unsafe_h) ? args.to_unsafe_h : args
        
        # Add retry logic for the job submission
        max_retries = 2
        retry_count = 0
        
        loop do
          begin
            response = HTTParty.post(
              "#{job_runner_url}/api/job_runner/run_job",
              body: {
                job_class: job_class,
                args: args_hash,
                secret: job_runner_secret
              }.to_json,
              headers: { 'Content-Type' => 'application/json' },
              timeout: 15 # Increased timeout for job submission
            )
            
            if response.success?
              Rails.logger.info "[JobRunnerService] Successfully delegated job #{job_class} to job runner. Job ID: #{response['job_id']}"
              return response['job_id']
            else
              error_message = "[JobRunnerService] Failed to delegate job #{job_class} to job runner. Status: #{response.code}, Error: #{response.body}"
              
              if retry_count < max_retries && (response.code >= 500 || response.code == 0)
                retry_count += 1
                Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
                sleep(2 * retry_count) # Exponential backoff
                next
              end
              
              Rails.logger.error error_message
              return false
            end
          rescue => e
            error_message = "[JobRunnerService] Error delegating job #{job_class} to job runner: #{e.message}"
            
            if retry_count < max_retries
              retry_count += 1
              Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
              sleep(2 * retry_count) # Exponential backoff
              next
            end
            
            Rails.logger.error error_message
            Rails.logger.error e.backtrace.join("\n")
            return false
          end
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Unexpected error delegating job #{job_class} to job runner: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        return false
      end
    end
    
    def run_specific_job(job_class, method_name, args = {})
      return false unless job_runner_enabled?
      
      Rails.logger.info "[JobRunnerService] Delegating specific job #{job_class}##{method_name} to job runner service with args: #{args.inspect}"
      
      begin
        # First ensure the job runner is awake with retries
        unless wake_up_job_runner(max_retries: 3)
          Rails.logger.error "[JobRunnerService] Job runner is not responding after retries. Cannot delegate job #{job_class}##{method_name}"
          return false
        end
        
        # Ensure args is a regular hash, not an ActionController::Parameters object
        args_hash = args.respond_to?(:to_unsafe_h) ? args.to_unsafe_h : args
        
        # Add retry logic for the job submission
        max_retries = 2
        retry_count = 0
        
        loop do
          begin
            response = HTTParty.post(
              "#{job_runner_url}/api/job_runner/run_specific_job",
              body: {
                job_class: job_class,
                method_name: method_name,
                args: args_hash,
                secret: job_runner_secret
              }.to_json,
              headers: { 'Content-Type' => 'application/json' },
              timeout: 15 # Increased timeout for job submission
            )
            
            if response.success?
              Rails.logger.info "[JobRunnerService] Successfully delegated specific job #{job_class}##{method_name} to job runner. Job ID: #{response['job_id']}"
              return response['job_id']
            else
              error_message = "[JobRunnerService] Failed to delegate specific job #{job_class}##{method_name} to job runner. Status: #{response.code}, Error: #{response.body}"
              
              if retry_count < max_retries && (response.code >= 500 || response.code == 0)
                retry_count += 1
                Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
                sleep(2 * retry_count) # Exponential backoff
                next
              end
              
              Rails.logger.error error_message
              return false
            end
          rescue => e
            error_message = "[JobRunnerService] Error delegating specific job #{job_class}##{method_name} to job runner: #{e.message}"
            
            if retry_count < max_retries
              retry_count += 1
              Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
              sleep(2 * retry_count) # Exponential backoff
              next
            end
            
            Rails.logger.error error_message
            Rails.logger.error e.backtrace.join("\n")
            return false
          end
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Unexpected error delegating specific job #{job_class}##{method_name} to job runner: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        return false
      end
    end
    
    def check_job_status(job_id)
      return nil unless job_runner_enabled?
      
      begin
        max_retries = 1
        retry_count = 0
        
        loop do
          begin
            response = HTTParty.get(
              "#{job_runner_url}/api/job_runner/job_status/#{job_id}",
              query: { secret: job_runner_secret },
              headers: { 'Content-Type' => 'application/json' },
              timeout: 8 # Increased timeout
            )
            
            if response.success?
              return response.parsed_response
            else
              error_message = "[JobRunnerService] Failed to check job status for job ID #{job_id}. Status: #{response.code}, Error: #{response.body}"
              
              if retry_count < max_retries && (response.code >= 500 || response.code == 0)
                retry_count += 1
                Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
                sleep(1) # Short delay before retry
                next
              end
              
              Rails.logger.error error_message
              return nil
            end
          rescue => e
            error_message = "[JobRunnerService] Error checking job status for job ID #{job_id}: #{e.message}"
            
            if retry_count < max_retries
              retry_count += 1
              Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
              sleep(1) # Short delay before retry
              next
            end
            
            Rails.logger.error error_message
            return nil
          end
        end
      rescue => e
        Rails.logger.error "[JobRunnerService] Unexpected error checking job status for job ID #{job_id}: #{e.message}"
        return nil
      end
    end
    
    def wake_up_job_runner(max_retries: 2)
      return true if Rails.env.development? || ENV['JOB_RUNNER_ONLY'] == 'true'
      
      retry_count = 0
      
      loop do
        begin
          Rails.logger.info "[JobRunnerService] Attempting to wake up job runner at #{job_runner_url}/health_check"
          
          response = HTTParty.get(
            "#{job_runner_url}/health_check",
            timeout: 12 # Increased timeout for health check
          )
          
          if response.success?
            Rails.logger.info "[JobRunnerService] Job runner is awake and healthy: #{response.body}"
            return true
          else
            error_message = "[JobRunnerService] Job runner health check failed. Status: #{response.code}, Error: #{response.body}"
            
            if retry_count < max_retries
              retry_count += 1
              Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
              sleep(3 * retry_count) # Longer delay for health check retries
              next
            end
            
            Rails.logger.error error_message
            return false
          end
        rescue => e
          error_message = "[JobRunnerService] Error waking up job runner: #{e.message}"
          
          if retry_count < max_retries
            retry_count += 1
            Rails.logger.warn "#{error_message}. Retrying (#{retry_count}/#{max_retries})..."
            sleep(3 * retry_count) # Longer delay for health check retries
            next
          end
          
          Rails.logger.error error_message
          return false
        end
      end
    rescue => e
      Rails.logger.error "[JobRunnerService] Unexpected error waking up job runner: #{e.message}"
      return false
    end
    
    # Check if the job runner is currently available
    def job_runner_available?
      return false if Rails.env.development? && ENV['USE_JOB_RUNNER'] != 'true'
      return false if ENV['JOB_RUNNER_ONLY'] == 'true'
      
      wake_up_job_runner(max_retries: 1)
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
