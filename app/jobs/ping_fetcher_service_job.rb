# frozen_string_literal: true

# Job to ping the fetcher service periodically to keep it awake
class PingFetcherServiceJob < ApplicationJob
  queue_as :default

  # Schedule this job to run periodically
  def self.schedule_ping
    # Only schedule if we're not already scheduled
    return if Rails.cache.read('ping_fetcher_service_scheduled')
    
    # Schedule the job to run in 10 minutes
    PingFetcherServiceJob.set(wait: 10.minutes).perform_later
    
    # Mark as scheduled
    Rails.cache.write('ping_fetcher_service_scheduled', true, expires_in: 15.minutes)
    
    Rails.logger.info "Scheduled PingFetcherServiceJob to run in 10 minutes"
  end

  def perform
    Rails.logger.info "PingFetcherServiceJob running at #{Time.now}"
    
    # Wake up the fetcher service
    result = JobRoutingService.wake_fetcher_service
    
    if result
      Rails.logger.info "Successfully pinged fetcher service"
    else
      Rails.logger.warn "Failed to ping fetcher service"
    end
    
    # Check if there are any pending jobs in fetcher queues
    if JobRoutingService.pending_fetcher_jobs?
      Rails.logger.info "There are pending jobs in fetcher queues"
    else
      Rails.logger.info "No pending jobs in fetcher queues"
    end
    
    # Schedule the next ping
    self.class.schedule_ping
    
    # Return the result
    result
  end
end 
