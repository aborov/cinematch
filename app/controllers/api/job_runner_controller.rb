module Api
  class JobRunnerController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_request
    
    def run_job
      job_class = params[:job_class]
      args = params[:args] || {}
      
      # Validate job class
      unless valid_job_class?(job_class)
        return render json: { error: "Invalid job class: #{job_class}" }, status: :bad_request
      end
      
      # Run the job
      begin
        job = job_class.constantize.perform_later(args)
        render json: { job_id: job.job_id, status: 'scheduled' }
      rescue => e
        Rails.logger.error "[JobRunnerController] Error scheduling job #{job_class}: #{e.message}"
        render json: { error: e.message }, status: :internal_server_error
      end
    end
    
    def run_specific_job
      job_class = params[:job_class]
      method_name = params[:method_name]
      args = params[:args] || {}
      
      # Validate job class
      unless valid_job_class?(job_class)
        return render json: { error: "Invalid job class: #{job_class}" }, status: :bad_request
      end
      
      # Validate method name
      unless valid_method_name?(method_name)
        return render json: { error: "Invalid method name: #{method_name}" }, status: :bad_request
      end
      
      # Run the job with the specific method
      begin
        job_class_constant = job_class.constantize
        job = if method_name.present?
                job_class_constant.send(method_name, args)
              else
                job_class_constant.perform_later(args)
              end
        
        job_id = job.respond_to?(:job_id) ? job.job_id : 'immediate'
        render json: { job_id: job_id, status: 'scheduled' }
      rescue => e
        Rails.logger.error "[JobRunnerController] Error scheduling job #{job_class}##{method_name}: #{e.message}"
        render json: { error: e.message }, status: :internal_server_error
      end
    end
    
    def job_status
      job_id = params[:job_id]
      
      unless job_id.present?
        return render json: { error: "Missing job_id parameter" }, status: :bad_request
      end
      
      job = GoodJob::Job.find_by(active_job_id: job_id)
      
      if job.nil?
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
      
      render json: {
        job_id: job.active_job_id,
        status: status,
        scheduled_at: job.scheduled_at,
        performed_at: job.performed_at,
        finished_at: job.finished_at,
        error: job.error.present? ? job.error : nil
      }
    end
    
    def health_check
      render json: { status: 'ok', timestamp: Time.current }
    end
    
    private
    
    def authenticate_request
      # Skip authentication for health check
      return true if action_name == 'health_check'
      
      # Simple authentication using a shared secret
      provided_secret = params[:secret] || (request.headers['Content-Type'] == 'application/json' ? JSON.parse(request.body.read)['secret'] : nil)
      expected_secret = ENV['SECRET_KEY_BASE'].to_s[0..15]
      
      unless provided_secret.present? && provided_secret == expected_secret
        render json: { error: 'Unauthorized' }, status: :unauthorized
        return false
      end
      
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
      
      allowed_job_classes.include?(job_class)
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
      
      allowed_method_names.include?(method_name)
    end
  end
end 
