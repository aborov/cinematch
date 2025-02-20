class FetchContentJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "[FetchContentJob] Starting job with operations: #{options.keys.join(', ')}"
    @start_time = Time.current
    
    if options[:fetch_new] || options.empty?
      Rails.logger.info "[FetchContentJob] Daily content fetch - Started at #{@start_time.strftime('%H:%M:%S')}"
      fetch_new_content
    end
    
    if options[:update_existing] || options.empty?
      Rails.logger.info "[FetchContentJob] Bi-weekly content update - Started at #{@start_time.strftime('%H:%M:%S')}"
      update_existing_content
    end
    
    if options[:fill_missing] || options.empty?
      Rails.logger.info "[FetchContentJob] Missing details fill - Started at #{@start_time.strftime('%H:%M:%S')}"
      fill_missing_details
    end
    
    duration = Time.current - @start_time
    Rails.logger.info "[FetchContentJob] Job completed in #{duration.round(2)}s. Total content items: #{Content.count}"
    UpdateAllRecommendationsJob.set(wait: 1.minute).perform_later
  rescue => e
    Rails.logger.error "[FetchContentJob] Failed after #{(Time.current - @start_time).round(2)}s: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end

  private

  def fetch_new_content
    Rails.logger.info "[FetchContentJob][New Content] Starting fetch"
    Rake::Task['tmdb:fetch_content'].invoke
    Rake::Task['tmdb:fetch_content'].reenable
  end

  def update_existing_content
    Rails.logger.info "[FetchContentJob][Update] Starting update of existing content"
    Rake::Task['tmdb:update_content'].invoke
    Rake::Task['tmdb:update_content'].reenable
  end

  def fill_missing_details
    Rails.logger.info "[FetchContentJob][Fill Missing] Starting missing details fill"
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
  end
end
