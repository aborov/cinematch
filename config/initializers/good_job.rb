Rails.application.configure do
  config.good_job.preserve_job_records = false
  config.good_job.retry_on_unhandled_error = true
  config.good_job.on_thread_error = -> (exception) { Rails.logger.error(exception) }
  config.good_job.execution_mode = :inline
  config.good_job.queues = '*'
  config.good_job.max_threads = 2
  config.good_job.poll_interval = 30 # seconds
  config.good_job.shutdown_timeout = 300 # 5 minutes
  config.good_job.enable_cron = true
  config.good_job.cron = {
    fetch_content: {
      cron: "5 9 * * *",  # Run daily at 9:05am UTC (3:05am CST)
      class: "FetchContentJob"
    }
  }
  config.good_job.cleanup_interval = 15.minutes
  config.good_job.cleanup_interval_jobs = 1000
  config.good_job.cleanup_interval_seconds = 1800
  config.good_job.max_cache = 5
end
