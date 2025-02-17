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
    # Trigger recommendations update after content fetch
    UpdateAllRecommendationsJob.perform_later
  rescue => e
    Rails.logger.error "FetchContentJob failed: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end

  private

  def fetch_new_content
    Rails.logger.info "Fetching new content"
    Rake::Task['tmdb:fetch_content'].invoke
    Rake::Task['tmdb:fetch_content'].reenable
  end

  def update_existing_content
    Rails.logger.info "Updating existing content"
    Rake::Task['tmdb:update_content'].invoke
    Rake::Task['tmdb:update_content'].reenable
  end

  def fill_missing_details
    Rails.logger.info "Filling missing details"
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
  end
end
