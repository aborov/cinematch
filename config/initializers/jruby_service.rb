# frozen_string_literal: true

# Configuration for JRuby service integration
Rails.application.config.after_initialize do
  # Only configure if not running on JRuby (i.e., in the main MRI Ruby app)
  if RUBY_ENGINE != 'jruby'
    # Set up JRuby service URL from environment or use a default for development
    jruby_service_url = ENV['JRUBY_SERVICE_URL'] || 'http://localhost:3001'
    
    # Store the URL in a global configuration
    Rails.application.config.jruby_service_url = jruby_service_url
    
    # Log the configuration
    Rails.logger.info "JRuby service configured with URL: #{jruby_service_url}"
    
    # Set up a periodic ping to keep the JRuby service awake on Render free tier
    if defined?(GoodJob::Scheduler) && Rails.env.production?
      Rails.logger.info "Setting up periodic ping for JRuby service"
      
      # Schedule a job to ping the JRuby service every 10 minutes to prevent it from sleeping
      GoodJob::Scheduler.instance.schedule(
        cron: '*/10 * * * *', # Every 10 minutes
        class: 'PingJrubyServiceJob',
        args: {},
        set: { queue: 'default' }
      )
    end
    
    # For development environment, add a flag to simulate JRuby service
    if Rails.env.development?
      Rails.application.config.simulate_jruby = true
      Rails.logger.info "Development mode: JRuby service simulation enabled"
    end
    
    # Monkey patch ActiveJob to route jobs to JRuby when appropriate
    ActiveJob::Base.class_eval do
      class_attribute :jruby_job, default: false
      
      # Allow jobs to be marked as JRuby jobs
      def self.runs_on_jruby
        self.jruby_job = true
      end
      
      # Override the perform_later method to route JRuby jobs appropriately
      module JRubyJobRouting
        def perform_later(*args)
          if self.class.jruby_job && defined?(JobRoutingService)
            Rails.logger.info "Routing job #{self.class.name} to JRuby service"
            
            # In development, we can simulate JRuby service by logging and running locally
            if Rails.env.development? && Rails.application.config.simulate_jruby
              Rails.logger.info "SIMULATING JRUBY SERVICE: Would send job #{self.class.name} with args: #{args.inspect}"
              Rails.logger.info "Job would be processed on queue: #{JobRoutingService.determine_queue(self.class)}"
              
              # Actually run the job locally for testing
              Rails.logger.info "DEVELOPMENT MODE: Running JRuby job locally for testing"
              return super
            end
            
            # Use JobRoutingService to handle JRuby jobs
            JobRoutingService.enqueue(self.class, *args)
          else
            super
          end
        end
      end
      
      # Include the module to override perform_later
      include JRubyJobRouting
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
      GoodJob.configuration.execution_mode = :inline
      GoodJob.configuration.queues = 'content_fetching,recommendations'
      GoodJob.configuration.max_threads = 5
      GoodJob.configuration.poll_interval = 30
    end
  end
end 
