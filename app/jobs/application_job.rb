# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Include the FetcherJobConcern to provide the runs_on_fetcher method
  include FetcherJobConcern
  
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Log job execution for tracking purposes
  def log_job_execution(job_id, args)
    Rails.logger.info "Executing job #{self.class.name} (#{job_id}) with args: #{args.inspect}"
  rescue => e
    Rails.logger.error "Error logging job execution: #{e.message}"
  end

  # Override perform to add routing logic
  def self.perform_later(*args)
    # For fetcher jobs, we need to route them to the fetcher service
    if self.fetcher_job && defined?(JobRoutingService) && !running_on_fetcher?
      Rails.logger.info "Routing job #{self.name} to fetcher service"
      
      # In development, we can simulate fetcher service by logging and running locally
      if Rails.env.development? && Rails.application.config.respond_to?(:simulate_fetcher) && Rails.application.config.simulate_fetcher
        Rails.logger.info "SIMULATING FETCHER SERVICE: Would send job #{self.name} with args: #{args.inspect}"
        
        # In development mode, we can run the job locally for testing
        # This is useful for debugging without having to run a separate service
        Rails.logger.info "DEVELOPMENT MODE: Running fetcher job locally for testing"
        return super
      end
      
      # Use JobRoutingService to handle fetcher jobs
      # This will wake up the fetcher service and enqueue the job
      JobRoutingService.enqueue(self, *args)
    else
      # For regular jobs, use the standard ActiveJob mechanism
      super
    end
  end
  
  # Add a method to check if we're running on the fetcher service
  def self.running_on_fetcher?
    ENV['SIMULATE_FETCHER'] == 'true'
  end
end
