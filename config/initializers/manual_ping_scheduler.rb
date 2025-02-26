# frozen_string_literal: true

# This initializer provides a fallback mechanism for scheduling the ping job
# if GoodJob's cron functionality isn't available

Rails.application.config.after_initialize do
  # Only run in production and if we're not running on JRuby
  if Rails.env.production? && RUBY_ENGINE != 'jruby' && defined?(PingJrubyServiceJob)
    # Check if we need to use the manual scheduler
    begin
      # Try to access GoodJob's cron functionality
      if !defined?(GoodJob) || 
         (!GoodJob.respond_to?(:configure) && 
          !(defined?(GoodJob::Scheduler) && GoodJob::Scheduler.respond_to?(:instance)))
        
        Rails.logger.info "Using manual scheduler for PingJrubyServiceJob"
        
        # Start a thread that will enqueue the ping job every 10 minutes
        Thread.new do
          # Wait for Rails to fully initialize
          sleep 30
          
          Rails.logger.info "Manual scheduler for PingJrubyServiceJob started"
          
          loop do
            begin
              # Enqueue the ping job
              Rails.logger.info "Manually enqueueing PingJrubyServiceJob"
              PingJrubyServiceJob.perform_later
              
              # Wait 10 minutes
              sleep 600
            rescue => e
              Rails.logger.error "Error in manual ping scheduler: #{e.message}"
              # Wait a bit before trying again
              sleep 60
            end
          end
        end
      end
    rescue => e
      Rails.logger.error "Error setting up manual ping scheduler: #{e.message}"
    end
  end
end 
