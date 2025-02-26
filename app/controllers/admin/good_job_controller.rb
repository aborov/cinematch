module Admin
  class GoodJobController < Admin::BaseController
    def dashboard
      @jobs = GoodJob::Job.all
      @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
      @next_fetch_job = GoodJob::Job.where(job_class: 'FetchContentJob').scheduled.first
      @next_update_job = GoodJob::Job.where(job_class: 'UpdateAllRecommendationsJob').scheduled.first
    end
    
    def show
      @job = GoodJob::Job.find(params[:id])
      render 'admin/good_job/error_details'
    end
    
    def run
      job = GoodJob::Job.find(params[:id])
      if job.finished_at.nil? && job.error.nil?
        job_class = job.job_class.constantize
        job_args = job.serialized_params.dig('arguments')
        job_class.perform_later(*job_args)
        flash[:notice] = "Job #{job.id} has been queued to run"
      else
        flash[:alert] = "Job #{job.id} cannot be run (already finished or has errors)"
      end
      redirect_to admin_good_job_dashboard_path
    end
    
    def retry
      job = GoodJob::Job.find(params[:id])
      if job.error.present?
        job_class = job.job_class.constantize
        job_args = job.serialized_params.dig('arguments')
        
        # Special handling for FetchContentJob to avoid serialization issues
        if job_class == FetchContentJob && job_args.is_a?(Array) && job_args.first.is_a?(Hash)
          # Convert any hash with symbol keys to string keys
          options = job_args.first.stringify_keys
          job_class.perform_later(options)
        else
          # For other job types, use the original arguments
          job_class.perform_later(*job_args)
        end
        
        flash[:notice] = "Job #{job.id} has been retried"
      else
        flash[:alert] = "Job #{job.id} cannot be retried (no errors)"
      end
      redirect_to admin_good_job_dashboard_path
    end
    
    def delete
      job = GoodJob::Job.find(params[:id])
      job.destroy
      flash[:notice] = "Job #{job.id} has been deleted"
      redirect_to admin_good_job_dashboard_path
    end
    
    def cancel
      job = GoodJob::Job.find(params[:id])
      
      if job.finished_at.present?
        flash[:alert] = "Job #{job.id} is already finished and cannot be cancelled"
      elsif job.error.present?
        flash[:alert] = "Job #{job.id} has already failed and cannot be cancelled"
      else
        # Use our JobCancellationService to cancel the job
        if JobCancellationService.cancel_job(job.id)
          # Force a more aggressive cancellation by also updating the job directly
          job.update(
            finished_at: Time.current, 
            error: "Cancelled by user at #{Time.current}",
            error_event: { 
              error_type: "Cancelled", 
              message: "Job was manually cancelled by admin user"
            }
          )
          
          # Try to kill any running processes associated with this job
          begin
            # This is a more aggressive approach to ensure the job stops
            if Rails.env.production?
              # In production, we'll rely on the database flag
              flash[:notice] = "Job #{job.id} has been cancelled. It may take a moment to stop completely."
            else
              # In development/test, we can be more aggressive
              GC.start(full_mark: true, immediate_sweep: true)
              flash[:notice] = "Job #{job.id} has been cancelled and cleanup initiated."
            end
          rescue => e
            Rails.logger.error "Error during aggressive job cancellation: #{e.message}"
            flash[:notice] = "Job #{job.id} has been marked as cancelled, but may still be running."
          end
        else
          flash[:alert] = "Failed to cancel job #{job.id}"
        end
      end
      
      redirect_to admin_good_job_dashboard_path
    end
    
    def run_job
      job_class = params[:job_class]
      
      # Log the parameters received from the form
      Rails.logger.info "Running job #{job_class} with parameters: #{params.inspect}"
      
      # Get memory management parameters from the form
      memory_threshold_mb = params[:memory_threshold_mb].presence&.to_i
      memory_critical_mb = params[:memory_critical_mb].presence&.to_i
      max_batch_size = params[:max_batch_size].presence&.to_i
      batch_size = params[:batch_size].presence&.to_i
      min_batch_size = params[:min_batch_size].presence&.to_i
      processing_batch_size = params[:processing_batch_size].presence&.to_i
      
      # Log the parameters that will be used
      Rails.logger.info "Memory parameters for job: threshold=#{memory_threshold_mb}MB, critical=#{memory_critical_mb}MB, " +
                        "max_batch=#{max_batch_size}, batch=#{batch_size}, min_batch=#{min_batch_size}, processing_batch=#{processing_batch_size}"
      
      # Create options hash with the parameters
      options = {
        action: params[:action_type],
        memory_threshold_mb: memory_threshold_mb,
        memory_critical_mb: memory_critical_mb,
        max_batch_size: max_batch_size,
        batch_size: batch_size,
        min_batch_size: min_batch_size,
        processing_batch_size: processing_batch_size
      }.compact
      
      # Queue the job with the options
      case job_class
      when 'FetchContentJob'
        job = FetchContentJob.perform_later(options)
        flash[:notice] = "FetchContentJob queued with action: #{params[:action_type]}"
      when 'UpdateRecommendationsJob'
        job = UpdateRecommendationsJob.perform_later
        flash[:notice] = "UpdateRecommendationsJob queued"
      else
        flash[:alert] = "Unknown job class: #{job_class}"
      end
      
      redirect_to admin_good_job_dashboard_path
    end
    
    helper_method :job_status, :admin_good_job_path, :enqueued_at
    
    private
    
    def set_memory_management_env_vars
      # Set environment variables for memory management if provided
      # These will be used by the job when it starts
      ENV['MEMORY_THRESHOLD_MB'] = params[:memory_threshold_mb] if params[:memory_threshold_mb].present?
      ENV['MAX_BATCH_SIZE'] = params[:max_batch_size] if params[:max_batch_size].present?
      ENV['BATCH_SIZE'] = params[:batch_size] if params[:batch_size].present?
      ENV['PROCESSING_BATCH_SIZE'] = params[:processing_batch_size] if params[:processing_batch_size].present?
      ENV['MIN_BATCH_SIZE'] = params[:min_batch_size] if params[:min_batch_size].present?
      
      # Log the values to help with debugging
      Rails.logger.info "Setting memory management ENV vars: " + 
                       "MEMORY_THRESHOLD_MB=#{ENV['MEMORY_THRESHOLD_MB']}, " +
                       "MAX_BATCH_SIZE=#{ENV['MAX_BATCH_SIZE']}, " +
                       "BATCH_SIZE=#{ENV['BATCH_SIZE']}, " +
                       "PROCESSING_BATCH_SIZE=#{ENV['PROCESSING_BATCH_SIZE']}, " +
                       "MIN_BATCH_SIZE=#{ENV['MIN_BATCH_SIZE']}"
    end
    
    def job_status(job)
      return 'Failed' if job.error.present?
      return 'Finished' if job.finished_at
      return 'Running' if job.performed_at
      'Queued'
    end
    
    def admin_good_job_path(job)
      admin_good_job_show_path(id: job.id)
    end
    
    def enqueued_at(job)
      return nil unless job.serialized_params
      params = job.serialized_params.is_a?(String) ? JSON.parse(job.serialized_params) : job.serialized_params
      params['enqueued_at']&.to_time&.strftime('%Y-%m-%d %H:%M:%S')
    rescue JSON::ParserError
      nil
    end
  end
end 
