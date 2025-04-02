class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FetchContentJob with options: #{options}"
    
    if options[:fetch_new] || options.empty?
      Rails.logger.info "Fetching new content"
      Rake::Task['tmdb:fetch_content'].invoke
      Rake::Task['tmdb:fetch_content'].reenable
    end
    
    if options[:update_existing] || options.empty?
      Rails.logger.info "Updating existing content"
      Rake::Task['tmdb:update_content'].invoke
      Rake::Task['tmdb:update_content'].reenable
    end
    
    if options[:fill_missing] || options.empty?
      Rails.logger.info "Filling missing details"
      Rake::Task['tmdb:fill_missing_details'].invoke
      Rake::Task['tmdb:fill_missing_details'].reenable
    end
    
    Rails.logger.info "FetchContentJob completed successfully"
    UpdateAllRecommendationsJob.perform_later
  rescue => e
    Rails.logger.error "FetchContentJob failed: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end
end
