Rails.application.configure do
  config.good_job = {
    execution_mode: :async,
    max_threads: ENV.fetch("GOOD_JOB_MAX_THREADS", 5).to_i,
    poll_interval: ENV.fetch("GOOD_JOB_POLL_INTERVAL", 30).to_i,
    shutdown_timeout: ENV.fetch("GOOD_JOB_SHUTDOWN_TIMEOUT", 25).to_i,
    queues: '*',
    max_cache: ENV.fetch("GOOD_JOB_MAX_CACHE", 10000).to_i,
    preserve_job_records: ENV.fetch("GOOD_JOB_PRESERVE_JOB_RECORDS", true) == 'true',
    retry_on_unhandled_error: ENV.fetch("GOOD_JOB_RETRY_ON_UNHANDLED_ERROR", false) == 'true',
    on_thread_error: -> (exception) { Rails.logger.error("GoodJob execution error: #{exception.inspect}") },
    cleanup_preserved_jobs_before_seconds_ago: 1.day.to_i,
    cleanup_interval_seconds: 1.hour.to_i,
    enable_cron: Rails.env.development? || Rails.env.job_runner? || ENV.fetch("JOB_RUNNER_ONLY", "false") == "true"
  }

  # Enable cron jobs only in development or on the job runner instance
  if config.good_job[:enable_cron]
    config.good_job[:cron] = {
      # Update all recommendations daily at 2 AM
      update_all_recommendations: {
        cron: "0 2 * * *",
        class: "UpdateAllRecommendationsJob"
      },
      # Fetch new content daily at 1 AM
      fetch_content: {
        cron: "0 1 * * *",
        class: "FetchContentJob"
      },
      # Fill missing details for movies and shows twice a day
      fill_missing_details: {
        cron: "0 */12 * * *",
        class: "FillMissingDetailsJob"
      }
    }
  end
end
