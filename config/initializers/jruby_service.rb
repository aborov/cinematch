# frozen_string_literal: true

# Configuration for JRuby service integration
Rails.application.config.after_initialize do
  # Only configure if not running on JRuby (i.e., in the main MRI Ruby app)
  if RUBY_ENGINE != 'jruby'
    # Set up JRuby service URL from environment or use a default for development
    jruby_service_url = ENV['JRUBY_SERVICE_URL']
    
    if jruby_service_url.present?
      Rails.logger.info "JRuby service URL from environment: #{jruby_service_url}"
    else
      # Default for development
      jruby_service_url = 'http://localhost:3001'
      Rails.logger.info "JRuby service URL not found in environment, using default: #{jruby_service_url}"
      
      if Rails.env.production?
        Rails.logger.warn "WARNING: Running in production but JRUBY_SERVICE_URL is not set. JRuby jobs may not work correctly."
      end
    end
    
    # Store the URL in a global configuration
    Rails.application.config.jruby_service_url = jruby_service_url
    
    # For development environment, add a flag to simulate JRuby service
    if Rails.env.development?
      Rails.application.config.simulate_jruby = true
      Rails.logger.info "Development mode: JRuby service simulation enabled"
    end
    
    # We don't need to monkey patch ActiveJob here since we've already
    # implemented the routing logic in ApplicationJob
    Rails.logger.info "JRuby service integration configured for main app"
    
    # Schedule the ping job to keep the JRuby service awake
    if Rails.env.production? && defined?(PingJrubyServiceJob)
      Rails.logger.info "Ensuring PingJrubyServiceJob is scheduled"
      # The actual scheduling is done in the GoodJob configuration
    end
    
    # IMPORTANT: Configure the main app to NOT process JRuby queues
    if defined?(GoodJob) && GoodJob.configuration.respond_to?(:queues=)
      # Get all queues except JRuby queues
      jruby_queues = JobRoutingService::JRUBY_QUEUES
      Rails.logger.info "Configuring main app to exclude JRuby queues: #{jruby_queues.join(', ')}"
      
      # Set the queues to process - exclude JRuby queues
      # Use a negated queue pattern to exclude JRuby queues
      excluded_queues = jruby_queues.map { |q| "!#{q}" }
      GoodJob.configuration.queues = "*,#{excluded_queues.join(',')}"
      
      Rails.logger.info "Main app configured to process queues: #{GoodJob.configuration.queues}"
    end
  else
    # Running on JRuby - log this fact
    Rails.logger.info "Running on JRuby #{JRUBY_VERSION}"
    
    # Configure JRuby-specific settings
    if defined?(Java)
      # Set JRuby GC strategy
      java.lang.System.setProperty('jruby.gc.strategy', 'balanced')
      
      # Enable invokedynamic which can improve performance
      java.lang.System.setProperty('jruby.compile.invokedynamic', 'true')
      
      Rails.logger.info "JRuby configured with optimized settings"
      
      # Configure Good Job to run in inline mode on JRuby
      # This allows the web process to process jobs without a separate worker
      Rails.logger.info "Configuring Good Job to run in inline mode on JRuby"
      
      # IMPORTANT: Configure JRuby to ONLY process JRuby queues
      if defined?(GoodJob) && GoodJob.configuration.respond_to?(:queues=)
        jruby_queues = JobRoutingService::JRUBY_QUEUES
        GoodJob.configuration.queues = jruby_queues.join(',')
        GoodJob.configuration.execution_mode = :async_server
        GoodJob.configuration.max_threads = 5
        GoodJob.configuration.poll_interval = 30
        
        Rails.logger.info "JRuby service configured to process queues: #{GoodJob.configuration.queues}"
        Rails.logger.info "JRuby service execution mode: #{GoodJob.configuration.execution_mode}"
      end
      
      Rails.logger.info "JRuby service ready to process jobs"
    end
  end
end 
