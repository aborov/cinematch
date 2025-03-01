require_relative "production"

Rails.application.configure do
  # Use production as the base but override specific settings
  
  # Disable asset compilation and related features
  config.assets.compile = false
  config.assets.digest = false
  config.assets.debug = false
  config.assets.enabled = false
  
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
  
  # Increase connection pool for background jobs
  config.active_record.database_pool = ENV.fetch("DB_POOL") { 10 }
  
  # Disable asset host
  config.action_controller.asset_host = nil
  
  # Disable public file server
  config.public_file_server.enabled = false
end 
