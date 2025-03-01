# Minimal Puma configuration for job runner service
# This configuration is optimized for background job processing with minimal memory usage

# Set the environment
environment ENV.fetch("RAILS_ENV") { "job_runner" }

# Specify the number of workers (processes)
# For a free tier, we want to keep this minimal
workers ENV.fetch("WEB_CONCURRENCY") { 1 }

# Specify the number of threads per worker
# Minimal configuration for job processing
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
threads 1, threads_count

# Set the port
port ENV.fetch("PORT") { 3000 }

# Preload the application
preload_app!

# Set the directory
directory ENV.fetch("RAILS_ROOT") { "." }

# Logging
stdout_redirect "log/puma_job_runner.log", "log/puma_job_runner_error.log", true unless ENV["RAILS_LOG_TO_STDOUT"] == "true"

# Set up hooks
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Reduce memory usage
before_fork do
  GC.compact if defined?(GC) && GC.respond_to?(:compact)
end 
