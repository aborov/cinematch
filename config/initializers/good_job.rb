# frozen_string_literal: true

# Configure GoodJob for background job processing
Rails.application.configure do
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = true
  config.good_job.on_thread_error = -> (exception) { Rails.logger.error(exception) }
  
  # Set execution mode based on environment
  # In development, use inline mode for simplicity
  # In production, use async_server mode to process jobs in the background
  config.good_job.execution_mode = Rails.env.development? ? :inline : :async_server
  
  # Configure queues and threads - this will be overridden for JRuby in jruby_service.rb
  # For MRI Ruby, we'll exclude JRuby queues in jruby_service.rb
  config.good_job.queues = '*'
  config.good_job.max_threads = 2
  config.good_job.poll_interval = 30 # seconds
  config.good_job.shutdown_timeout = 300 # 5 minutes
  
  # Enable cron jobs
  config.good_job.enable_cron = true
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
    },
    ping_jruby_service: {
      cron: "*/10 * * * *",  # Every 10 minutes
      class: "PingJrubyServiceJob",
      args: {}
    }
  }
  
  # Cleanup settings
  config.good_job.cleanup_interval = 15.minutes
  config.good_job.cleanup_interval_jobs = 1000
  config.good_job.cleanup_interval_seconds = 1800
  config.good_job.max_cache = 5
end

# Additional configuration for development environment
if Rails.env.development?
  Rails.application.config.good_job[:execution_mode] = :inline
end

# Log the current configuration
Rails.application.config.after_initialize do
  # Only log if we're not in JRuby - JRuby will log its own configuration
  if RUBY_ENGINE != 'jruby'
    Rails.logger.info "GoodJob configured with execution_mode: #{Rails.application.config.good_job.execution_mode}"
    Rails.logger.info "GoodJob max_threads: #{Rails.application.config.good_job.max_threads}"
    Rails.logger.info "Running on Ruby engine: #{RUBY_ENGINE}"
  end
end
