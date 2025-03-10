Rails.application.configure do
  config.good_job = {
    execution_mode: :async,
    max_threads: ENV.fetch("GOOD_JOB_MAX_THREADS", 5).to_i,
    poll_interval: ENV.fetch("GOOD_JOB_POLL_INTERVAL", 30).to_i,
    shutdown_timeout: ENV.fetch("GOOD_JOB_SHUTDOWN_TIMEOUT", 25).to_i,
    queues: ENV.fetch("GOOD_JOB_QUEUES", "*"),
    max_cache: ENV.fetch("GOOD_JOB_MAX_CACHE", 5000).to_i,
    preserve_job_records: true,
    retry_on_unhandled_error: ENV.fetch("GOOD_JOB_RETRY_ON_UNHANDLED_ERROR", false) == 'true',
    on_thread_error: -> (exception) { 
      Rails.logger.error("GoodJob execution error: #{exception.inspect}\n#{exception.backtrace.join("\n")}")
      # Run memory monitor on thread error if it's defined
      if defined?(Rake::Task) && Rake::Task.task_defined?('memory:monitor')
        Rake::Task['memory:monitor'].invoke
        Rake::Task['memory:monitor'].reenable
      end
    },
    cleanup_preserved_jobs_before_seconds_ago: 2.weeks.to_i,
    cleanup_interval_seconds: 1.day.to_i,
    enable_cron: Rails.env.development? || Rails.env.job_runner? || ENV.fetch("JOB_RUNNER_ONLY", "false") == "true",
    queue_select_limit: ENV.fetch("GOOD_JOB_QUEUE_SELECT_LIMIT", 50).to_i,
    # Configure queue priorities
    queue_priorities: {
      # Higher priority queues
      content_fetching: 10,
      recommendations: 5,
      # Default priority
      default: 1
    }
  }

  # Enable cron jobs only in development or on the job runner instance
  if config.good_job[:enable_cron]
    config.good_job[:cron] = {
      # Fetch new content daily at 1 AM UTC (8 PM CDT)
      fetch_new_content: {
        cron: "0 1 * * *",
        class: "FetchContentJob",
        args: { "fetch_new" => true }
      },
      
      # Update existing content with significant changes three times a week
      # Monday, Wednesday, Friday at 3 AM UTC (10 PM CDT)
      update_content: {
        cron: "0 3 * * 1,3,5",
        class: "FetchContentJob",
        args: { "update_existing" => true }
      },
      
      # Fill missing details once a week on Sunday at 4 AM UTC (11 PM CDT)
      fill_missing_details: {
        cron: "0 4 * * 0",
        class: "FetchContentJob",
        args: { "fill_missing" => true }
      }
    }
  end
end

# Add a callback to monitor memory after job execution
# This is done outside the configuration block to avoid initialization issues
if defined?(GoodJob::Job)
  module MemoryMonitorCallback
    def self.after_perform(job)
      # Run memory monitoring more frequently for heavy jobs
      # For regular jobs, only run occasionally to reduce overhead
      should_monitor = if ['FetchContentJob', 'UpdateAllRecommendationsJob', 'FillMissingDetailsJob'].include?(job.job_class)
        # Run for 50% of heavy jobs
        rand < 0.5
      else
        # Run for 5% of regular jobs
        rand < 0.05
      end
      
      if should_monitor
        if defined?(Rake::Task) && Rake::Task.task_defined?('memory:monitor')
          begin
            Rake::Task['memory:monitor'].invoke
            Rake::Task['memory:monitor'].reenable
          rescue => e
            Rails.logger.error "[MemoryMonitorCallback] Error running memory:monitor: #{e.message}"
          end
        end
      end
      
      # Clear Active Record query cache after each job
      if defined?(ActiveRecord::Base)
        begin
          ActiveRecord::Base.connection.clear_query_cache
        rescue => e
          Rails.logger.error "[MemoryMonitorCallback] Error clearing query cache: #{e.message}"
        end
      end
      
      # Force garbage collection more aggressively after heavy jobs
      if ['FetchContentJob', 'UpdateAllRecommendationsJob', 'FillMissingDetailsJob'].include?(job.job_class)
        begin
          GC.start
          GC.compact if GC.respond_to?(:compact)
          Rails.logger.info "[MemoryMonitorCallback] Forced garbage collection after heavy job: #{job.job_class}"
        rescue => e
          Rails.logger.error "[MemoryMonitorCallback] Error during garbage collection: #{e.message}"
        end
      end
    end
  end

  # Register the callback if we're not in the asset precompilation process
  unless $PROGRAM_NAME.include?('assets:precompile') || ARGV.include?('assets:precompile')
    GoodJob::Job.after_perform do |job|
      MemoryMonitorCallback.after_perform(job)
    end
  end
end
