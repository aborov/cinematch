class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FetchContentJob with options: #{options}"
    
    if options[:fetch_new] || options.empty?
      fetch_new_content
    end
    
    if options[:update_existing] || options.empty?
      update_existing_content
    end
    
    if options[:fill_missing] || options.empty?
      fill_missing_details
    end
    
    Rails.logger.info "FetchContentJob completed successfully"
    # Add delay before starting recommendations update
    UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
  rescue => e
    Rails.logger.error "FetchContentJob failed: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end
end
