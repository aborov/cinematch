class FillMissingDetailsJob < ApplicationJob
  queue_as :default

  def perform
    # If we're not on the job runner instance, delegate the job to the job runner service
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production?
      Rails.logger.info "[FillMissingDetailsJob] Running in production on main app, delegating to job runner service"
      
      # First wake up the job runner
      unless JobRunnerService.wake_up_job_runner
        Rails.logger.warn "[FillMissingDetailsJob] Failed to wake up job runner. Running locally instead."
      else
        job_id = JobRunnerService.run_job('FillMissingDetailsJob')
        
        if job_id
          Rails.logger.info "[FillMissingDetailsJob] Successfully delegated to job runner. Job ID: #{job_id}"
          return
        else
          Rails.logger.warn "[FillMissingDetailsJob] Failed to delegate to job runner. Running locally instead."
        end
      end
    else
      Rails.logger.info "[FillMissingDetailsJob] Running on job runner or in development, executing locally"
    end
    
    require 'rake'
    Rails.application.load_tasks
    
    start_time = Time.current
    Rails.logger.info "[FillMissingDetailsJob] Starting to fill missing details"
    
    Rake::Task['tmdb:fill_missing_details'].invoke
    Rake::Task['tmdb:fill_missing_details'].reenable
    
    duration = Time.current - start_time
    Rails.logger.info "[FillMissingDetailsJob] Completed filling missing details in #{duration.round(2)}s"
  end
  
  # Class method for direct invocation
  def self.fill_missing_details
    if ENV['JOB_RUNNER_ONLY'] != 'true' && Rails.env.production?
      Rails.logger.info "[FillMissingDetailsJob] Delegating fill_missing_details to job runner"
      JobRunnerService.wake_up_job_runner
      job_id = JobRunnerService.run_specific_job('FillMissingDetailsJob', 'fill_missing_details')
      
      if job_id
        Rails.logger.info "[FillMissingDetailsJob] Successfully delegated fill_missing_details to job runner. Job ID: #{job_id}"
      else
        Rails.logger.warn "[FillMissingDetailsJob] Failed to delegate to job runner. Running locally instead."
        new.perform
      end
    else
      Rails.logger.info "[FillMissingDetailsJob] Running fill_missing_details locally"
      new.perform
    end
  end
end 
