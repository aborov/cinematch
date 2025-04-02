# Minimal Puma configuration for job runner service
# This configuration is optimized for background job processing with minimal memory usage

# Set the environment
environment ENV.fetch("RAILS_ENV") { "production" }

# Use single mode instead of cluster mode
# This reduces memory overhead and prevents hitting API rate limits
workers 0

# Specify the number of threads
# Minimal configuration for job processing to avoid memory issues on free tier
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 3 }
threads 1, threads_count

# Set the port - Render expects this to be explicitly bound
port_number = ENV.fetch("PORT") { 3000 }
bind "tcp://0.0.0.0:#{port_number}"

# Set the directory
directory ENV.fetch("RAILS_ROOT") { "." }

# Logging - use stdout for Render
if ENV["RAILS_LOG_TO_STDOUT"] == "true"
  stdout_redirect
else
  stdout_redirect "log/puma_job_runner.log", "log/puma_job_runner_error.log", true
end

# Reduce memory usage
before_fork do
  GC.compact if defined?(GC) && GC.respond_to?(:compact)
end

# Set process name to make it easier to identify
tag "cinematch-job-runner"

# Set lower backlog for reduced memory usage
backlog_limit = ENV.fetch("PUMA_BACKLOG_LIMIT") { 16 }
set_remote_address "proxy_protocol"

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Low-level tweaks to reduce memory usage
# These settings help reduce memory footprint
nakayoshi_fork true if respond_to?(:nakayoshi_fork)
fork_worker if respond_to?(:fork_worker) 
