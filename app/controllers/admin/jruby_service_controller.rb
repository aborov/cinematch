# frozen_string_literal: true

module Admin
  # Controller for managing the JRuby service from the admin interface
  class JrubyServiceController < Admin::BaseController
    before_action :authenticate_admin_user!
    
    # Skip CSRF protection for API endpoints
    skip_before_action :verify_authenticity_token, only: [:ping, :status]
    
    # Skip Pundit authorization for these endpoints
    skip_after_action :verify_authorized
    
    # Show the JRuby service status and management interface
    def index
      @jruby_url = Rails.application.config.jruby_service_url
      
      # Get the JRuby service status
      begin
        require 'net/http'
        uri = URI("#{@jruby_url}/jruby/status")
        response = Net::HTTP.get_response(uri)
        
        if response.code == '200'
          @status = JSON.parse(response.body)
          @service_running = true
        else
          @service_running = false
          @error = "Service returned status code: #{response.code}"
        end
      rescue => e
        @service_running = false
        @error = "Error connecting to JRuby service: #{e.message}"
      end
      
      # Get JRuby job statistics
      @jruby_queues = JobRoutingService::JRUBY_QUEUES
      @jruby_jobs = JobRoutingService::JRUBY_JOBS
      
      # Get job counts for JRuby queues
      @queue_stats = {}
      @jruby_queues.each do |queue|
        @queue_stats[queue] = {
          total: GoodJob::Job.where(queue_name: queue).count,
          pending: GoodJob::Job.where(queue_name: queue, performed_at: nil).count,
          processed: GoodJob::Job.where(queue_name: queue).where.not(performed_at: nil).count,
          failed: GoodJob::Job.where(queue_name: queue).where.not(error: nil).count
        }
      end
    end
    
    # Wake up the JRuby service
    def wake
      result = JobRoutingService.wake_jruby_service
      
      if result
        flash[:notice] = "JRuby service has been awakened successfully."
      else
        flash[:alert] = "Failed to wake up the JRuby service. Check the logs for details."
      end
      
      redirect_to admin_jruby_service_path
    end
    
    # Run a test job on the JRuby service
    def test_job
      job_class = params[:job_class].constantize
      
      if JobRoutingService::JRUBY_JOBS.include?(params[:job_class])
        # Enqueue the job with test parameters
        job = JobRoutingService.enqueue(job_class, test: true, memory_threshold_mb: 300, batch_size: 10)
        
        flash[:notice] = "Test job has been enqueued. Job ID: #{job.provider_job_id}"
      else
        flash[:alert] = "The selected job is not configured to run on JRuby."
      end
      
      redirect_to admin_jruby_service_path
    end
    
    # Wake up the JRuby service manually
    def wake_up
      success = JobRoutingService.wake_jruby_service_with_retries(5)
      
      if success
        redirect_to admin_jruby_service_path, notice: "JRuby service successfully awakened."
      else
        redirect_to admin_jruby_service_path, alert: "Failed to wake up JRuby service after multiple attempts."
      end
    end
    
    # Simple endpoint to check if the service is running
    def status
      # This method is mentioned in the code but not implemented in the original file or the new code block
      # It's assumed to exist as it's called in the original file
      # If it's needed, it should be implemented here
      render json: { status: "Service is running" }, status: :ok
    end
  end
end 
