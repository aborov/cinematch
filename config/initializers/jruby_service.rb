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
    
    # Monkey patch ActiveJob to route jobs to JRuby when appropriate
    ActiveJob::Base.class_eval do
      class_attribute :jruby_job, default: false
      
      class << self
        # Allow jobs to be marked as JRuby jobs
        def runs_on_jruby
          self.jruby_job = true
        end
        
        # Override the enqueue method to use JobRoutingService for JRuby jobs
        alias_method :original_enqueue, :enqueue
        
        def enqueue(*args)
          if self.jruby_job && defined?(JobRoutingService)
            JobRoutingService.enqueue(self, *args)
          else
            original_enqueue(*args)
          end
        end
        
        # Override the set method to use JobRoutingService for JRuby jobs
        alias_method :original_set, :set
        
        def set(options = {})
          if self.jruby_job && defined?(JobRoutingService) && options[:wait_until]
            JobRoutingService.schedule(self, options[:wait_until], options.except(:wait_until))
            return self
          else
            original_set(options)
          end
        end
      end
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
