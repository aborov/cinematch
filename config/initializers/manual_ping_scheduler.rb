# frozen_string_literal: true

# This initializer sets up a manual scheduler for pinging the fetcher service
# This is needed because GoodJob's cron scheduler doesn't always work reliably in production
# It schedules the ping job for the fetcher service

# Only run in production
if Rails.env.production? && defined?(PingFetcherServiceJob)
  # Create a thread to schedule the ping job
  Thread.new do
    # Wait for Rails to fully initialize
    sleep 30

    begin
      # Log that we're using the manual scheduler
      Rails.logger.info "Using manual scheduler for PingFetcherServiceJob"
      
      # Schedule the ping job
      PingFetcherServiceJob.schedule_ping
      
      # Log that the scheduler has started
      Rails.logger.info "Manual scheduler for PingFetcherServiceJob started"
      
      # Every 10 minutes, check if the job is scheduled and schedule it if not
      loop do
        sleep 10.minutes
        
        # Log that we're manually enqueueing the job
        Rails.logger.info "Manually enqueueing PingFetcherServiceJob"
        PingFetcherServiceJob.perform_later
      end
    rescue => e
      # Log any errors
      Rails.logger.error "Error in manual ping scheduler: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end 
