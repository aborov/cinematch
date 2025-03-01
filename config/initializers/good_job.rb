Rails.application.configure do
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = true
  config.good_job.on_thread_error = -> (exception) { Rails.logger.error(exception) }
  config.good_job.execution_mode = Rails.env.development? ? :inline : :async
  config.good_job.queues = '*'
  config.good_job.max_threads = 2
  config.good_job.poll_interval = 30 # seconds
  config.good_job.shutdown_timeout = 300 # 5 minutes
  
  # Only enable cron jobs on the main app in development or if we're on the job runner in production
  config.good_job.enable_cron = Rails.env.development? || ENV['JOB_RUNNER_ONLY'] == 'true'
  
  # Define cron jobs
  config.good_job.cron = {
    fetch_new_content: {
      cron: "0 9 * * *",  # Daily at 09:00 UTC (3:00 AM CST)
      class: "FetchContentJob",
      args: [{ fetch_new: true }]
    },
    update_existing_content: {
      cron: "0 21 * * *",  # Daily at 21:00 UTC (3:00 PM CST)
      class: "FetchContentJob",
      args: [{ update_existing: true }]
    },
    fill_missing_details: {
      cron: "0 4 * * 2,5",  # Tuesday/Friday at 04:00 UTC (10:00 PM CST Mon/Thu)
      class: "FetchContentJob",
      args: [{ fill_missing: true }]
    }
  }
  
  config.good_job.cleanup_interval = 15.minutes
  config.good_job.cleanup_interval_jobs = 1000
  config.good_job.cleanup_interval_seconds = 1800
  config.good_job.max_cache = 5
end
