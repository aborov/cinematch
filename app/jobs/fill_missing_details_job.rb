class FillMissingDetailsJob < ApplicationJob
  queue_as :default

  def perform
    # If we're not on the job runner instance and the job runner URL is configured,
    # delegate the job to the job runner service
    if !ENV['JOB_RUNNER_ONLY'] && ENV['JOB_RUNNER_URL'].present?
      Rails.logger.info "[FillMissingDetailsJob] Delegating to job runner service"
      job_id = JobRunnerService.run_job('FillMissingDetailsJob')
      
      if job_id
        Rails.logger.info "[FillMissingDetailsJob] Successfully delegated to job runner. Job ID: #{job_id}"
        return
      else
        Rails.logger.warn "[FillMissingDetailsJob] Failed to delegate to job runner. Running locally instead."
      end
    end
    
    require 'rake'
    Rails.application.load_tasks
    
    Rails.logger.info "Starting FillMissingDetailsJob"
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
    Rails.logger.info "FillMissingDetailsJob completed"
  end
end 
