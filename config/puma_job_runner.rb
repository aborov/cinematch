# Puma configuration file for the job runner service
# This configuration is optimized for low memory usage

# Minimum and Maximum threads per worker
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { 1 }
threads min_threads_count, max_threads_count

# Use the `PORT` environment variable provided by Render
port ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
environment ENV.fetch("RAILS_ENV") { "production" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma_job_runner.pid" }

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Set very conservative worker settings for free tier
workers ENV.fetch("WEB_CONCURRENCY") { 1 }
preload_app!

# Set lower timeout for job runner
worker_timeout 60

# Reduce memory usage by forcing garbage collection more frequently
before_fork do
  GC.compact if defined?(GC) && GC.respond_to?(:compact)
end

on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Disconnect from database when shutting down
on_worker_shutdown do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end 
