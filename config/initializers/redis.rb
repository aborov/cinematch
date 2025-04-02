# Redis configuration for Cinematch
# This initializer sets up Redis connections for various parts of the application

require 'redis'

# Skip Redis initialization during asset precompilation to avoid connection errors
if ($PROGRAM_NAME.include?('assets:precompile') || ARGV.include?('assets:precompile')) && !Rails.env.development?
  # Create null Redis objects for asset precompilation
  class NullRedis
    def method_missing(method, *args, &block)
      nil
    end
    
    def respond_to_missing?(method, include_private = false)
      true
    end
    
    def ping
      "PONG"
    end
  end
  
  $redis = $redis_cache = $redis_jobs = NullRedis.new
  Rails.logger.info "Using NullRedis during asset precompilation"
else
  # Configure Redis URL from environment or use default
  REDIS_URL = ENV.fetch('REDIS_URL') { 'redis://cinematch-redis:6379' }
  
  # Configure Redis connection options
  REDIS_OPTIONS = {
    url: REDIS_URL,
    timeout: 5.0,
    reconnect_attempts: 3,
    reconnect_delay: 0.5,
    reconnect_delay_max: 2.0,
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }.freeze
  
  # Create Redis connections for different purposes
  begin
    # Main Redis connection
    $redis = Redis.new(REDIS_OPTIONS.merge(db: 0))
    
    # Redis for caching (if not using Rails.cache)
    $redis_cache = Redis.new(REDIS_OPTIONS.merge(db: 1))
    
    # Redis for job queues
    $redis_jobs = Redis.new(REDIS_OPTIONS.merge(db: 2))
    
    # Test Redis connection
    $redis.ping
    
    Rails.logger.info "Redis connected successfully to #{REDIS_URL}"
  rescue Redis::CannotConnectError => e
    Rails.logger.error "Failed to connect to Redis: #{e.message}"
    
    # Fallback to a null Redis implementation if Redis is unavailable
    # This allows the app to start even if Redis is down
    class NullRedis
      def method_missing(method, *args, &block)
        Rails.logger.warn "Redis unavailable, NullRedis called: #{method}"
        nil
      end
      
      def respond_to_missing?(method, include_private = false)
        true
      end
      
      def ping
        "PONG"
      end
    end
    
    $redis = $redis_cache = $redis_jobs = NullRedis.new
  end
  
  # Configure Redis for memory management
  # Only run this in production to avoid development issues
  if Rails.env.production?
    begin
      # Check if we have permission to set config
      # Some managed Redis services (like Render's free tier) don't allow CONFIG commands
      begin
        # Try a simple CONFIG GET command first to test permissions
        $redis_cache.call('CONFIG', 'GET', 'maxmemory-policy')
        
        # If we get here, we have permission to use CONFIG commands
        # Set memory policy to LRU (Least Recently Used) for cache database
        $redis_cache.call('CONFIG', 'SET', 'maxmemory-policy', 'allkeys-lru')
        
        # Set maximum memory usage (80% of available Redis memory)
        # For the free tier with 25MB, we'll set it to 20MB
        $redis_cache.call('CONFIG', 'SET', 'maxmemory', '20mb')
        
        Rails.logger.info "Redis memory policy configured successfully"
      rescue Redis::CommandError => e
        if e.message.include?('NOPERM') || e.message.include?('permission')
          Rails.logger.info "Skipping Redis memory policy configuration: insufficient permissions (this is normal for managed Redis services)"
        else
          raise e
        end
      end
    rescue => e
      Rails.logger.error "Failed to configure Redis memory policy: #{e.message}"
    end
  end
end 
