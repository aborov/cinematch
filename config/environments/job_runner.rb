require_relative "production"

Rails.application.configure do
  # Use production as the base but override specific settings
  
  # Allow requests from the job runner domain
  config.hosts << "cinematch-job-runner.onrender.com"
  config.hosts << "cinematch-ywet.onrender.com"
  
  # Disable asset compilation and related features
  config.assets.compile = false
  config.assets.digest = false
  config.assets.debug = false
  
  # Disable view rendering optimizations
  config.action_view.cache_template_loading = false
  
  # Disable unnecessary middleware
  config.middleware.delete ActionDispatch::Static
  
  # Increase logging for job runner
  config.log_level = :info
  
  # Disable action cable
  config.action_cable.mount_path = nil
  
  # Optimize for background jobs
  config.active_job.queue_adapter = :good_job
  
  # Set database pool size through database.yml instead
  # Rails 7.1 handles this differently
  
  # Disable asset host
  config.action_controller.asset_host = nil
  
  # Disable public file server
  config.public_file_server.enabled = false
  
  # Enable stdout logging
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end
  
  # Disable asset pipeline for job runner
  config.assets.enabled = false
  
  # Disable template rendering for views that require assets
  config.action_controller.asset_host = nil
  
  # Set consider_all_requests_local to false to prevent detailed error pages
  config.consider_all_requests_local = false
end 
