class FillMissingDetailsJob < ApplicationJob
  queue_as :default

  def perform
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FillMissingDetailsJob"
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
    Rails.logger.info "FillMissingDetailsJob completed"
  end
end 
