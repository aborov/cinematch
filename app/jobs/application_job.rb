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
      JobRoutingService.enqueue(self, *args)
    else
      super
    end
  end
end
