# frozen_string_literal: true

# This initializer schedules the ping job for the fetcher service
# It runs after all other initializers (hence the z_ prefix)

# Only schedule the ping job in production
if Rails.env.production? && defined?(PingFetcherServiceJob)
  begin
    Rails.logger.info "Scheduling PingFetcherServiceJob from initializer"
    PingFetcherServiceJob.schedule_ping
  rescue => e
    Rails.logger.error "Failed to schedule PingFetcherServiceJob: #{e.message}"
  end
end 
