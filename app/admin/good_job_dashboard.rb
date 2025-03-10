ActiveAdmin.register_page "Good Job Dashboard" do
  menu priority: 2, label: "Job Dashboard"

  # Add a page_action route for the check_job_runner action
  page_action :check_job_runner, method: :get

  content title: "Good Job Dashboard" do
    # Add meta tag with job runner URL
    meta name: "job-runner-url", content: JobRunnerService.send(:job_runner_url)
    
    div class: "good-job-dashboard" do
      # Local job status section
      div class: "local-job-status" do
        h2 "Local Job Status"
        render partial: 'admin/good_job/local_dashboard'
      end

      # Job runner status section with dynamic updates
      div class: "job-runner-status" do
        h2 "Job Runner Status"
        div id: "job-runner-status-container" do
          render partial: 'admin/good_job/job_runner_status'
        end
      end
    end

    # Include JavaScript for dynamic updates
    script src: asset_path('admin/good_job_dashboard.js'), type: 'text/javascript'
  end

  action_item :fetch_content do
    link_to 'Fetch Content', admin_good_job_dashboard_run_fetch_new_content_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to fetch new content?' }
  end

  action_item :update_content do
    link_to 'Update Content', admin_good_job_dashboard_run_update_existing_content_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to update existing content?' }
  end

  action_item :fill_missing_details do
    link_to 'Fill Missing Details', admin_good_job_dashboard_run_fill_missing_content_details_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to fill missing content details?' }
  end

  action_item :update_recommendations do
    link_to 'Update Recommendations', admin_good_job_dashboard_run_update_recommendations_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to update recommendations for all users?' }
  end

  action_item :check_job_runner do
    link_to 'Check Job Runner', admin_good_job_dashboard_check_job_runner_path, 
            class: 'admin-job-button'
  end

  page_action :run_fetch_content, method: :post do
    authorize :page, :run_fetch_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob')
    else
      job = FetchContentJob.perform_later
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Content fetch job started (Job ID: #{job_id})"
  end

  page_action :run_fetch_new_content, method: :post do
    authorize :page, :run_fetch_new_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { fetch_new: true })
    else
      job = FetchContentJob.perform_later(fetch_new: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fetch new content job started (Job ID: #{job_id})"
  end

  page_action :run_update_existing_content, method: :post do
    authorize :page, :run_update_existing_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { update_existing: true })
    else
      job = FetchContentJob.perform_later(update_existing: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Update existing content job started (Job ID: #{job_id})"
  end

  page_action :run_fill_missing_content_details, method: :post do
    authorize :page, :run_fill_missing_content_details?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { fill_missing: true })
    else
      job = FetchContentJob.perform_later(fill_missing: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fill missing content details job started (Job ID: #{job_id})"
  end

  page_action :run_update_recommendations, method: :post do
    authorize :page, :run_update_recommendations?
    
    batch_size = params[:batch_size].present? ? params[:batch_size].to_i : 50
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('UpdateAllRecommendationsJob', { batch_size: batch_size })
    else
      job = UpdateAllRecommendationsJob.perform_later(batch_size: batch_size)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Update recommendations job started with batch size #{batch_size} (Job ID: #{job_id})"
  end

  page_action :run_fill_missing_details, method: :post do
    authorize :page, :run_fill_missing_details?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FillMissingDetailsJob')
    else
      job = FillMissingDetailsJob.perform_later
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fill missing details job started (Job ID: #{job_id})"
  end

  page_action :delete_job, method: :delete do
    authorize :page, :delete_job?
    
    job_id = params[:id]
    # Use find_by_id to avoid exceptions if the job doesn't exist
    job = GoodJob::Job.find_by(id: job_id)
    
    if job
      job_class = job.job_class
      # Ensure the job is properly destroyed
      if job.destroy
        # Clear any potential caches
        GoodJob::Job.uncached do
          # Force a reload of the jobs collection
          GoodJob::Job.connection.clear_query_cache
          redirect_to admin_good_job_dashboard_path, notice: "Job #{job_class} (ID: #{job_id}) has been deleted from history"
        end
      else
        redirect_to admin_good_job_dashboard_path, alert: "Failed to delete job #{job_class} (ID: #{job_id})"
      end
    else
      redirect_to admin_good_job_dashboard_path, alert: "Job with ID #{job_id} not found"
    end
  end

  controller do
    helper_method :job_status, :can_delete_job?, :job_display_name
    
    # Skip authentication for AJAX requests to check_job_runner
    skip_before_action :authenticate_active_admin_user, only: :check_job_runner, if: -> { request.xhr? }
    
    # Handle authorization errors gracefully
    rescue_from Pundit::NotAuthorizedError do |exception|
      Rails.logger.error "Authorization error in GoodJobDashboard: #{exception.message}"
      if request.xhr?
        render json: { error: 'Not authorized', status: 'error' }, status: :forbidden
      else
        flash[:error] = "You are not authorized to access this page."
        redirect_to admin_good_job_dashboard_path
      end
    end
    
    skip_before_action :authorize_access!, only: :check_job_runner
    
    def check_job_runner
      # Add explicit admin check
      unless current_user&.admin?
        flash[:error] = "You are not authorized to perform this action."
        redirect_to admin_good_job_dashboard_path and return
      end
      
      begin
        @job_runner_status = {}
        
        if ENV['JOB_RUNNER_ONLY'] == 'true'
          # This instance is the job runner
          @job_runner_status = {
            status: 'ok',
            message: 'This is the job runner instance',
            is_job_runner: true,
            is_available: true,
            active_jobs: GoodJob::Job.where.not(performed_at: nil).where(finished_at: nil).count,
            queued_jobs: GoodJob::Job.where(performed_at: nil).count,
            recent_errors: GoodJob::Job.where.not(error: nil).order(created_at: :desc).limit(5)
          }
        elsif Rails.env.development? && ENV['USE_JOB_RUNNER'] != 'true'
          # In development without job runner enabled
          @job_runner_status = {
            status: 'info',
            message: 'Job runner is disabled in development. Set USE_JOB_RUNNER=true to enable.',
            is_available: false,
            is_development: true
          }
        else
          begin
            # Force a real check of the job runner status
            job_runner_available = JobRunnerService.send(:wake_up_job_runner, max_retries: 1)
            
            if job_runner_available
              @job_runner_status = {
                status: 'ok',
                message: 'Job runner is available',
                is_available: true
              }
              
              # Try to get more details
              begin
                Rails.logger.info "[GoodJobDashboard] Fetching job runner details"
                
                response = HTTParty.get(
                  "#{JobRunnerService.send(:job_runner_url)}/api/job_runner/status",
                  timeout: 5
                )
                
                if response.success?
                  status_data = response.parsed_response
                  Rails.logger.info "[GoodJobDashboard] Successfully fetched job runner details: #{status_data.except('recent_errors').inspect}"
                  
                  @job_runner_status[:details] = status_data
                else
                  error_message = "Job runner status endpoint returned error: #{response.code}"
                  Rails.logger.warn "[GoodJobDashboard] #{error_message}"
                  @job_runner_status[:details_error] = error_message
                end
              rescue => e
                error_message = "Error fetching job runner details: #{e.message}"
                Rails.logger.error "[GoodJobDashboard] #{error_message}"
                @job_runner_status[:details_error] = error_message
              end
            else
              @job_runner_status = {
                status: 'error',
                message: 'Job runner is not available',
                is_available: false
              }
            end
          rescue => e
            Rails.logger.error "Error checking job runner: #{e.message}\n#{e.backtrace.join("\n")}"
            @job_runner_status = {
              status: 'error',
              message: "Error checking job runner: #{e.message}",
              is_available: false
            }
          end
        end
        
        respond_to do |format|
          format.html do
            if request.xhr?
              render partial: 'admin/good_job/job_runner_status', layout: false
            else
              redirect_to admin_good_job_dashboard_path, notice: @job_runner_status[:message]
            end
          end
          format.json { render json: @job_runner_status }
        end
      rescue => e
        Rails.logger.error "Error in check_job_runner: #{e.message}\n#{e.backtrace.join("\n")}"
        respond_to do |format|
          format.html do
            flash[:error] = "An error occurred: #{e.message}"
            redirect_to admin_good_job_dashboard_path
          end
          format.json { render json: { error: e.message }, status: :internal_server_error }
        end
      end
    end

    def index
      # Ensure we're getting fresh data
      begin
        GoodJob::Job.uncached do
          GoodJob::Job.connection.clear_query_cache
          @jobs = GoodJob::Job.where('created_at > ?', 2.weeks.ago)
          @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
          @job_classes = GoodJob::Job.distinct.pluck(:job_class).compact.sort
          @next_fetch_job = GoodJob::Job.where(job_class: 'FetchContentJob').scheduled.first
          @next_update_job = GoodJob::Job.where(job_class: 'UpdateAllRecommendationsJob').scheduled.first
          @next_fill_details_job = GoodJob::Job.where(job_class: 'FillMissingDetailsJob').scheduled.first
        end
      rescue => e
        Rails.logger.error "Error fetching job data: #{e.message}\n#{e.backtrace.join("\n")}"
        @jobs = []
        @queues = []
        @job_classes = []
        @next_fetch_job = nil
        @next_update_job = nil
        @next_fill_details_job = nil
      end
      
      # Initialize job runner status without waiting
      @job_runner_status = {
        status: 'checking',
        message: 'Checking job runner status...',
        is_available: false
      }
    end

    private

    def job_status(job)
      return 'Failed' if job.error.present?
      return 'Finished' if job.finished_at
      return 'Running' if job.performed_at
      'Queued'
    end
    
    def job_display_name(job)
      # Regular display for non-FetchContentJob jobs
      return job.job_class unless job.job_class == 'FetchContentJob'
      
      # Parse the serialized_params to extract options
      begin
        # Ensure we have valid serialized_params
        return job.job_class unless job.serialized_params.present?
        
        # Handle different serialized_params formats
        params_hash = nil
        begin
          if job.serialized_params.is_a?(Hash)
            params_hash = job.serialized_params
          elsif job.serialized_params.is_a?(String)
            params_hash = JSON.parse(job.serialized_params)
          else
            params_hash = JSON.parse(job.serialized_params.to_s)
          end
        rescue => e
          Rails.logger.error "Error parsing serialized_params: #{e.message}"
          return job.job_class
        end
        
        # Ensure we have valid arguments
        return job.job_class unless params_hash.is_a?(Hash) && params_hash['arguments'].present?
        
        arguments = params_hash['arguments']
        
        # Handle different argument formats
        options = {}
        begin
          if arguments.is_a?(Array) && arguments.size > 0
            first_arg = arguments.first
            
            # Handle different types of first argument
            if first_arg.is_a?(Hash)
              options = first_arg
            elsif first_arg.is_a?(String) && first_arg.start_with?('{')
              # Try to parse as JSON
              options = JSON.parse(first_arg)
            elsif first_arg.is_a?(String)
              # Simple string parameter
              options = { 'input' => first_arg }
            elsif first_arg.is_a?(TrueClass) || first_arg.is_a?(FalseClass)
              # Boolean parameter
              options = { 'fetch_new' => first_arg }
            elsif first_arg.is_a?(Integer)
              # Integer parameter
              options = { 'batch_size' => first_arg }
            end
          end
        rescue => e
          Rails.logger.error "Error parsing job arguments: #{e.message}"
          return "#{job.job_class} (Error: #{e.message})"
        end
        
        # Determine operation type
        operation_type = if options['fetch_new'] || (options.is_a?(Hash) && options[:fetch_new])
          'Fetch New Content'
        elsif options['update_existing'] || (options.is_a?(Hash) && options[:update_existing])
          'Update Existing Content'
        elsif options['fill_missing'] || (options.is_a?(Hash) && options[:fill_missing])
          'Fill Missing Details'
        else
          'All Operations'
        end
        
        # Return formatted job name
        "#{job.job_class}: #{operation_type}"
      rescue => e
        Rails.logger.error "Error in job_display_name: #{e.message}\n#{e.backtrace.join("\n")}"
        "#{job.job_class} (Error)"
      end
    end
    
    def can_delete_job?
      current_user.admin?
    end

    # Add a rescue_from block to handle errors
    rescue_from StandardError do |e|
      Rails.logger.error "Error in GoodJobDashboard: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:error] = "An error occurred: #{e.message}"
      redirect_to admin_good_job_dashboard_path
    end
  end
end
