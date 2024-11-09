class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FetchContentJob with options: #{options}"
    
    # Execute each task in its own transaction
    fetch_new_content if options[:fetch_new] || options.empty?
    update_existing_content if options[:update_existing] || options.empty?
    fill_missing_details if options[:fill_missing] || options.empty?
    
    Rails.logger.info "FetchContentJob completed successfully"
    UpdateAllRecommendationsJob.perform_later
  rescue => e
    Rails.logger.error "FetchContentJob failed: #{e.message}"
    raise e
  end

  private

  def fetch_new_content
    Rails.logger.info "Fetching new content"
    ActiveRecord::Base.transaction do
      Rake::Task['tmdb:fetch_content'].invoke
      Rake::Task['tmdb:fetch_content'].reenable
    end
  end

  def update_existing_content
    Rails.logger.info "Updating existing content"
    ActiveRecord::Base.transaction do
      Rake::Task['tmdb:update_content'].invoke
      Rake::Task['tmdb:update_content'].reenable
    end
  end

  def fill_missing_details
    Rails.logger.info "Filling missing details"
    ActiveRecord::Base.transaction do
      Rake::Task['tmdb:fill_missing_details'].invoke
      Rake::Task['tmdb:fill_missing_details'].reenable
    end
  end
end
