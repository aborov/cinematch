require 'httparty'

module Api
  class JobRunnerController < JobRunnerBaseController
    before_action :authenticate_request, except: [:health_check, :status]
    
    def health_check
      render json: { 
        status: 'ok', 
        timestamp: Time.current,
        environment: Rails.env,
        job_runner: ENV['JOB_RUNNER_ONLY'] == 'true',
        good_job_status: GoodJob::Job.count >= 0 ? 'connected' : 'error',
        version: '1.1' # Add a version to track changes
      }
    end
    
    # Public status endpoint to check if the job runner is available
    def status
      is_job_runner = ENV['JOB_RUNNER_ONLY'] == 'true'
      
      if is_job_runner
        # If we are the job runner, return our status
        render json: {
          status: 'ok',
          timestamp: Time.current,
          environment: Rails.env,
          job_runner: true,
          good_job_status: GoodJob::Job.count >= 0 ? 'connected' : 'error',
          active_jobs: GoodJob::Job.where.not(performed_at: nil).where(finished_at: nil).count,
          queued_jobs: GoodJob::Job.where(performed_at: nil).count,
          recent_errors: GoodJob::Job.where.not(error: nil).order(created_at: :desc).limit(5).map { |j| { id: j.id, job_class: j.job_class, error: j.error.to_s.truncate(100) } }
        }
      else
        # If we're not the job runner, check if the job runner is available
        begin
          job_runner_available = JobRunnerService.job_runner_available?
          
          if job_runner_available
            # If available, get more details from the job runner
            begin
              response = HTTParty.get(
                "#{JobRunnerService.send(:job_runner_url)}/api/job_runner/health_check",
                timeout: 5
              )
              
              if response.success?
                # Return the job runner's health check response
                render json: response.parsed_response.merge(
                  main_app_timestamp: Time.current,
                  job_runner_available: true
                )
              else
                render json: {
                  status: 'warning',
                  timestamp: Time.current,
                  job_runner_available: false,
                  error: "Job runner returned status code: #{response.code}"
                }
              end
            rescue => e
              render json: {
                status: 'warning',
                timestamp: Time.current,
                job_runner_available: false,
                error: "Error communicating with job runner: #{e.message}"
              }
            end
          else
            render json: {
              status: 'warning',
              timestamp: Time.current,
              job_runner_available: false,
              error: "Job runner is not responding"
            }
          end
        rescue => e
          render json: {
            status: 'error',
            timestamp: Time.current,
            job_runner_available: false,
            error: "Error checking job runner status: #{e.message}"
          }
        end
      end
    end
    
    def run_job
      job_class = params[:job_class]
      args = params[:args] || {}
      
      Rails.logger.info "[JobRunnerController] Received request to run job #{job_class} with args: #{args.inspect}"
      
      # Validate job class
      unless valid_job_class?(job_class)
        Rails.logger.error "[JobRunnerController] Invalid job class: #{job_class}"
        return render json: { error: "Invalid job class: #{job_class}" }, status: :bad_request
      end
      
      # Run the job
      begin
        job_class_constant = job_class.constantize
        Rails.logger.info "[JobRunnerController] Scheduling job #{job_class}"
        
        # Convert ActionController::Parameters to a regular hash
        args_hash = args.is_a?(ActionController::Parameters) ? args.permit!.to_h : args
        
        job = if args_hash.present?
          job_class_constant.perform_later(args_hash)
        else
          job_class_constant.perform_later
        end
        
        Rails.logger.info "[JobRunnerController] Successfully scheduled job #{job_class} with ID: #{job.job_id}"
        render json: { job_id: job.job_id, status: 'scheduled' }
      rescue => e
        Rails.logger.error "[JobRunnerController] Error scheduling job #{job_class}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
    
    def run_specific_job
      job_class = params[:job_class]
      method_name = params[:method_name]
      args = params[:args] || {}
      
      Rails.logger.info "[JobRunnerController] Received request to run specific job #{job_class}##{method_name} with args: #{args.inspect}"
      
      # Validate job class
      unless valid_job_class?(job_class)
        Rails.logger.error "[JobRunnerController] Invalid job class: #{job_class}"
        return render json: { error: "Invalid job class: #{job_class}" }, status: :bad_request
      end
      
      # Validate method name
      unless valid_method_name?(method_name)
        Rails.logger.error "[JobRunnerController] Invalid method name: #{method_name}"
        return render json: { error: "Invalid method name: #{method_name}" }, status: :bad_request
      end
      
      # Run the job with the specific method
      begin
        job_class_constant = job_class.constantize
        Rails.logger.info "[JobRunnerController] Calling method #{method_name} on #{job_class}"
        
        # Convert ActionController::Parameters to a regular hash
        args_hash = args.is_a?(ActionController::Parameters) ? args.permit!.to_h : args
        
        job = if method_name.present?
                job_class_constant.send(method_name, args_hash)
              else
                job_class_constant.perform_later(args_hash)
              end
        
        job_id = job.respond_to?(:job_id) ? job.job_id : 'immediate'
        Rails.logger.info "[JobRunnerController] Successfully called method #{method_name} on #{job_class}. Job ID: #{job_id}"
        render json: { job_id: job_id, status: 'scheduled' }
      rescue => e
        Rails.logger.error "[JobRunnerController] Error scheduling job #{job_class}##{method_name}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
    
    def job_status
      job_id = params[:job_id]
      
      unless job_id.present?
        Rails.logger.error "[JobRunnerController] Missing job_id parameter"
        return render json: { error: "Missing job_id parameter" }, status: :bad_request
      end
      
      Rails.logger.info "[JobRunnerController] Checking status for job ID: #{job_id}"
      job = GoodJob::Job.find_by(active_job_id: job_id)
      
      if job.nil?
        Rails.logger.error "[JobRunnerController] Job not found with ID: #{job_id}"
        return render json: { error: "Job not found" }, status: :not_found
      end
      
      status = if job.error.present?
                'failed'
              elsif job.finished_at.present?
                'completed'
              elsif job.performed_at.present?
                'running'
              else
                'scheduled'
              end
      
      Rails.logger.info "[JobRunnerController] Job #{job_id} status: #{status}"
      render json: {
        job_id: job.active_job_id,
        status: status,
        scheduled_at: job.scheduled_at,
        performed_at: job.performed_at,
        finished_at: job.finished_at,
        error: job.error.present? ? job.error : nil
      }
    end
    
    private
    
    def authenticate_request
      # Skip authentication for health check
      return true if action_name == 'health_check'
      
      # Simple authentication using a shared secret
      provided_secret = nil
      
      # Try to get the secret from various sources
      if params[:secret].present?
        provided_secret = params[:secret]
      elsif request.headers['Authorization'].present?
        provided_secret = request.headers['Authorization'].gsub(/^Bearer\s+/, '')
      elsif request.headers['Content-Type'] == 'application/json'
        begin
          body_params = JSON.parse(request.body.read)
          request.body.rewind
          provided_secret = body_params['secret']
        rescue JSON::ParserError
          # Ignore JSON parsing errors
        end
      end
      
      # Use a dedicated shared secret for job runner authentication
      # Fall back to SECRET_KEY_BASE if JOB_RUNNER_SECRET is not set
      expected_secret = ENV['JOB_RUNNER_SECRET'] || ENV['SECRET_KEY_BASE'].to_s[0..15]
      
      Rails.logger.info "[JobRunnerController] Authenticating request with secret: #{provided_secret.to_s[0..3]}..." if Rails.env.development?
      Rails.logger.info "[JobRunnerController] Expected secret: #{expected_secret[0..3]}..." if Rails.env.development?
      
      unless provided_secret.present? && provided_secret == expected_secret
        Rails.logger.error "[JobRunnerController] Unauthorized request. Secret mismatch or missing."
        render json: { error: 'Unauthorized' }, status: :unauthorized
        return false
      end
      
      Rails.logger.info "[JobRunnerController] Request authenticated successfully"
      true
    end
    
    def valid_job_class?(job_class)
      # Whitelist of allowed job classes
      allowed_job_classes = [
        'FetchContentJob',
        'FillMissingDetailsJob',
        'UpdateAllRecommendationsJob',
        'GenerateRecommendationsJob'
      ]
      
      is_valid = allowed_job_classes.include?(job_class)
      Rails.logger.info "[JobRunnerController] Job class #{job_class} validation: #{is_valid ? 'valid' : 'invalid'}"
      is_valid
    end
    
    def valid_method_name?(method_name)
      return true if method_name.blank?
      
      # Whitelist of allowed method names
      allowed_method_names = [
        'perform_later',
        'perform_now',
        'fetch_new_content',
        'update_existing_content',
        'fill_missing_details',
        'update_all_recommendations',
        'generate_recommendations_for_user'
      ]
      
      is_valid = allowed_method_names.include?(method_name)
      Rails.logger.info "[JobRunnerController] Method name #{method_name} validation: #{is_valid ? 'valid' : 'invalid'}"
      is_valid
    end
  end
end 
