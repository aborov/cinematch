# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Include the JrubyJobConcern to provide the runs_on_jruby method
  include JrubyJobConcern
  
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  
  # Override perform_later to route JRuby jobs appropriately
  def self.perform_later(*args)
    if self.jruby_job && defined?(JobRoutingService) && RUBY_ENGINE != 'jruby'
      Rails.logger.info "Routing job #{self.name} to JRuby service"
      
      # In development, we can simulate JRuby service by logging and running locally
      if Rails.env.development? && Rails.application.config.respond_to?(:simulate_jruby) && Rails.application.config.simulate_jruby
        Rails.logger.info "SIMULATING JRUBY SERVICE: Would send job #{self.name} with args: #{args.inspect}"
        Rails.logger.info "Job would be processed on queue: #{JobRoutingService.determine_queue(self)}"
        
        # Actually run the job locally for testing
        Rails.logger.info "DEVELOPMENT MODE: Running JRuby job locally for testing"
        return super
      end
      
      # Use JobRoutingService to handle JRuby jobs
      # This will wake up the JRuby service and enqueue the job
      return JobRoutingService.enqueue(self, *args)
    else
      # If we're already on JRuby or this is not a JRuby job, use the standard perform_later
      super
    end
  end
  
  # Add a method to check if we're running on JRuby
  def self.running_on_jruby?
    RUBY_ENGINE == 'jruby'
  end
  
  # Add a method to log job execution details
  def log_job_execution(job_id, args)
    Rails.logger.info "Executing job #{self.class.name} (ID: #{job_id}) on #{RUBY_ENGINE} with args: #{args.inspect}"
  end
end
