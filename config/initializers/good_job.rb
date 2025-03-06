Rails.application.configure do
  config.good_job = {
    execution_mode: :async,
    max_threads: ENV.fetch("GOOD_JOB_MAX_THREADS", 10).to_i,
    poll_interval: ENV.fetch("GOOD_JOB_POLL_INTERVAL", 15).to_i,
    shutdown_timeout: ENV.fetch("GOOD_JOB_SHUTDOWN_TIMEOUT", 25).to_i,
    queues: ENV.fetch("GOOD_JOB_QUEUES", "*"),
    max_cache: ENV.fetch("GOOD_JOB_MAX_CACHE", 10000).to_i,
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
    queue_select_limit: ENV.fetch("GOOD_JOB_QUEUE_SELECT_LIMIT", 100).to_i,
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
      # Update all recommendations daily at 2 AM UTC (9 PM CDT)
      update_all_recommendations: {
        cron: "0 2 * * *",
        class: "UpdateAllRecommendationsJob",
        args: { batch_size: 50 }
      },
      # Fetch new content daily at 1 AM UTC (8 PM CDT)
      fetch_content: {
        cron: "0 1 * * *",
        class: "FetchContentJob"
      },
      # Fill missing details for movies and shows twice a day
      fill_missing_details: {
        cron: "0 */12 * * *",
        class: "FillMissingDetailsJob"
      },
      # Run memory monitoring every hour
      memory_monitor: {
        cron: "0 * * * *",
        class: "GoodJob::ActiveJobJob",
        args: { task_name: "memory:monitor" }
      }
    }
  end
end

# Add a callback to monitor memory after job execution
# This is done outside the configuration block to avoid initialization issues
if defined?(GoodJob::Job)
  module MemoryMonitorCallback
    def self.after_perform(job)
      # Only run memory monitoring occasionally to reduce overhead
      if rand < 0.1 # 10% chance
        if defined?(Rake::Task) && Rake::Task.task_defined?('memory:monitor')
          Rake::Task['memory:monitor'].invoke
          Rake::Task['memory:monitor'].reenable
        end
      end
      
      # Clear Active Record query cache after each job
      if defined?(ActiveRecord::Base)
        ActiveRecord::Base.connection.clear_query_cache
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
