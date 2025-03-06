# Minimal Puma configuration for job runner service
# This configuration is optimized for background job processing with minimal memory usage

# Set the environment
environment ENV.fetch("RAILS_ENV") { "job_runner" }

# Use single mode instead of cluster mode with a single worker
# This reduces memory overhead as recommended by Puma
workers 0

# Specify the number of threads
# Minimal configuration for job processing
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
threads 1, threads_count

# Set the port - Render expects this to be explicitly bound
port_number = ENV.fetch("PORT") { 3000 }
# Only use one binding method - using bind is more explicit
bind "tcp://0.0.0.0:#{port_number}"

# Preload the application
preload_app!

# Set the directory
directory ENV.fetch("RAILS_ROOT") { "." }

# Logging - use stdout if configured
if ENV["RAILS_LOG_TO_STDOUT"] == "true"
  stdout_redirect
else
  stdout_redirect "log/puma_job_runner.log", "log/puma_job_runner_error.log", true
end

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

# Low-level tweaks to reduce memory usage
# These settings help reduce memory footprint
nakayoshi_fork true if respond_to?(:nakayoshi_fork)
fork_worker if respond_to?(:fork_worker)

# Set lower backlog for reduced memory usage
backlog_limit = ENV.fetch("PUMA_BACKLOG_LIMIT") { 16 }
set_remote_address "proxy_protocol", backlog_limit 
