class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FetchContentJob with options: #{options}"
    
    if options[:fetch_new] || options.empty?
      FetchNewContentJob.perform_later
    end
    
    if options[:update_existing] || options.empty?
      UpdateExistingContentJob.perform_later
    end
    
    if options[:fill_missing] || options.empty?
      FillMissingDetailsJob.perform_later
    end
    
    Rails.logger.info "FetchContentJob completed successfully"
    UpdateAllRecommendationsJob.perform_later
  rescue => e
    Rails.logger.error "FetchContentJob failed: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end
end
