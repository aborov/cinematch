require 'get_process_mem'

class MemoryMonitor
  attr_reader :memory_threshold, :max_batch_size, :min_batch_size
  attr_accessor :batch_size, :processing_batch_size
  
  # Track memory trend
  attr_reader :memory_readings
  
  def initialize(options = {})
    @memory_monitor = GetProcessMem.new
    @memory_threshold = options[:memory_threshold] || ENV.fetch('MEMORY_THRESHOLD_MB', 250).to_i
    @max_batch_size = options[:max_batch_size] || ENV.fetch('MAX_BATCH_SIZE', 50).to_i
    @batch_size = options[:batch_size] || ENV.fetch('BATCH_SIZE', 20).to_i
    @processing_batch_size = options[:processing_batch_size] || ENV.fetch('PROCESSING_BATCH_SIZE', 5).to_i
    @min_batch_size = options[:min_batch_size] || ENV.fetch('MIN_BATCH_SIZE', 3).to_i

    @memory_readings = []
    @critical_memory_threshold = @memory_threshold * 1.05  # Lower critical threshold to 5% above
    @warning_memory_threshold = @memory_threshold * 0.7    # Start reducing earlier at 70% of threshold
    @emergency_threshold = @memory_threshold * 1.2         # Emergency threshold at 20% above
    @consecutive_high_readings = 0                        # Track consecutive high readings
    @last_emergency_time = nil                            # Track when last emergency action was taken
    @last_compaction_time = nil                           # Track when last heap compaction was performed
    @compaction_interval = 180                            # Seconds between heap compactions (3 minutes)
    @memory_growth_rate = 0                               # Track memory growth rate
    @last_memory_reading = mb                             # Initialize last memory reading
    
    # Throttling parameters
    @last_throttle_check = Time.now
    @throttle_interval = 3                                # Check system load every 3 seconds
    @throttle_threshold = 0.7                             # Throttle when CPU usage is above 70%
    @throttle_pause_time = 3.0                            # Pause for 3 seconds when throttling
    
    puts "[MemoryMonitor] Initialized with threshold: #{@memory_threshold}MB, batch size: #{@batch_size}"
  end
  
  def mb
    @memory_monitor.mb
  end
  
  def track_memory
    current_memory = mb
    previous_memory = @memory_readings.last || current_memory
    
    # Calculate memory growth rate (MB per reading)
    @memory_growth_rate = current_memory - previous_memory
    
    @memory_readings << current_memory
    @memory_readings.shift if @memory_readings.size > 10  # Track more readings
    
    # Update consecutive high readings counter
    if current_memory > @memory_threshold
      @consecutive_high_readings += 1
    else
      @consecutive_high_readings = 0
    end
    
    # Store last memory reading
    @last_memory_reading = current_memory
    
    # Check if we need to throttle based on system load
    throttle_if_needed
    
    current_memory
  end
  
  def memory_trend_increasing?
    return false if @memory_readings.size < 3
    
    # Check if memory has been increasing over the last 3 readings
    @memory_readings[-1] > @memory_readings[-2] && @memory_readings[-2] > @memory_readings[-3]
  end
  
  def memory_growth_critical?
    # Check if memory growth rate is concerning (more than 2MB per reading)
    @memory_growth_rate > 2.0
  end
  
  def throttle_if_needed
    # Only check periodically to avoid excessive system calls
    return unless Time.now - @last_throttle_check > @throttle_interval
    
    begin
      # Get CPU usage (platform-specific)
      cpu_usage = get_cpu_usage
      
      if cpu_usage > @throttle_threshold
        puts "[MemoryMonitor] System load high (#{cpu_usage.round(2)}). Throttling for #{@throttle_pause_time} seconds..."
        sleep(@throttle_pause_time)
      end
    rescue => e
      # Don't fail if we can't get CPU usage
      puts "[MemoryMonitor] Error checking system load: #{e.message}"
    ensure
      @last_throttle_check = Time.now
    end
  end
  
  def get_cpu_usage
    case RUBY_PLATFORM
    when /darwin/
      # macOS
      load_avg = `sysctl -n vm.loadavg`.split[1].to_f
      processor_count = `sysctl -n hw.ncpu`.to_i
      load_avg / processor_count
    when /linux/
      # Linux
      load_avg = File.read('/proc/loadavg').split[0].to_f
      processor_count = File.read('/proc/cpuinfo').scan(/^processor/).count
      load_avg / processor_count
    else
      # Default to a conservative value if we can't determine
      0.7
    end
  rescue
    # If anything fails, return a moderate value
    0.5
  end
  
  def adjust_batch_size
    current_memory = track_memory
    old_batch_size = @batch_size
    old_processing_batch_size = @processing_batch_size
    
    # Check if heap compaction is due
    if GC.respond_to?(:compact) && (@last_compaction_time.nil? || (Time.now - @last_compaction_time) > @compaction_interval)
      puts "[Memory] Performing scheduled heap compaction..."
      compact_heap
      @last_compaction_time = Time.now
    end
    
    # Emergency situation - memory keeps growing despite previous reductions
    if (current_memory > @emergency_threshold) || 
       (@consecutive_high_readings >= 2 && memory_trend_increasing?) ||  # Reduced from 3 to 2
       (current_memory > @critical_memory_threshold && @batch_size <= @min_batch_size * 2) ||
       memory_growth_critical?
      
      # Only take emergency action once every 20 seconds (reduced from 30)
      if @last_emergency_time.nil? || (Time.now - @last_emergency_time) > 20
        puts "[Memory] EMERGENCY: #{current_memory.round(1)}MB. Memory continues to grow despite batch size reductions."
        emergency_memory_cleanup
        @last_emergency_time = Time.now
        
        # Set batch size to absolute minimum
        @batch_size = @min_batch_size
        @processing_batch_size = @min_batch_size
        
        puts "[Memory] EMERGENCY: Batch size reduced to minimum #{@batch_size}. Pausing processing for 15 seconds."
        sleep(15.0)  # Longer pause to allow memory to stabilize
        return true
      end
    end
    
    if current_memory > @critical_memory_threshold
      # Critical memory situation - reduce batch size drastically and force GC
      reduction_factor = 0.25  # More aggressive reduction
      @batch_size = [(@batch_size * reduction_factor).to_i, @min_batch_size].max
      @processing_batch_size = [(@processing_batch_size * reduction_factor).to_i, @min_batch_size].max
      puts "[Memory] CRITICAL: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{@batch_size}"
      force_gc(5.0) # Longer pause for critical situations
    elsif current_memory > @memory_threshold
      # Above threshold - reduce batch size and force GC
      reduction_factor = 0.4  # More aggressive reduction
      @batch_size = [(@batch_size * reduction_factor).to_i, @min_batch_size].max
      @processing_batch_size = [(@processing_batch_size * reduction_factor).to_i, @min_batch_size].max
      puts "[Memory] HIGH: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{@batch_size}"
      force_gc(3.0) # Longer pause for high memory
    elsif current_memory > @warning_memory_threshold || memory_trend_increasing?
      # Approaching threshold or trending up - reduce batch size moderately
      reduction_factor = 0.5  # More aggressive reduction
      @batch_size = [(@batch_size * reduction_factor).to_i, @min_batch_size].max
      @processing_batch_size = [(@processing_batch_size * reduction_factor).to_i, @min_batch_size].max
      puts "[Memory] WARNING: #{current_memory.round(1)}MB approaching threshold or trending up. Reducing batch size from #{old_batch_size} to #{@batch_size}"
      force_gc(2.0) # Longer pause for warning level
    elsif current_memory < @memory_threshold * 0.5 && @batch_size < @max_batch_size
      # If memory usage is low, gradually increase batch size
      # Be more conservative with increases
      @batch_size = [(@batch_size * 1.05).to_i, @max_batch_size].min
      @processing_batch_size = [(@processing_batch_size * 1.05).to_i, (@max_batch_size / 3).to_i].min
      puts "[Memory] LOW: #{current_memory.round(1)}MB. Increasing batch size from #{old_batch_size} to #{@batch_size}"
    end
    
    # Return true if batch size was changed
    old_batch_size != @batch_size || old_processing_batch_size != @processing_batch_size
  end
  
  def force_gc(sleep_time = 0.5)
    GC.start(full_mark: true, immediate_sweep: true)
    sleep(sleep_time) if sleep_time > 0
  end
  
  def compact_heap
    if GC.respond_to?(:compact)
      # First run GC to mark unused objects
      GC.start(full_mark: true, immediate_sweep: true)
      
      # Then compact the heap
      GC.compact
      
      # Log memory after compaction
      puts "[Memory] After heap compaction: #{mb.round(1)}MB"
    end
  end
  
  def aggressive_memory_cleanup
    # Force multiple GC cycles to ensure memory is released
    5.times do |i|  # Increased from 3 to 5 cycles
      puts "[Memory] Running GC cycle #{i+1}/5..."
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0)  # Longer sleep between GC cycles
    end
    
    # Compact the heap if supported
    compact_heap
    
    # Clear Ruby's object space to help with memory release
    if defined?(ObjectSpace) && ObjectSpace.respond_to?(:garbage_collect)
      ObjectSpace.garbage_collect
    end
    
    # Clear any temporary variables in the current scope
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.respond_to?(:clear_query_cache)
      ActiveRecord::Base.connection.clear_query_cache
    end
    
    # Reset database connections
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.respond_to?(:clear_reloadable_connections!)
      ActiveRecord::Base.connection_pool.clear_reloadable_connections!
    end
    
    # Try to disconnect and reconnect database
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.respond_to?(:disconnect!)
      begin
        puts "[Memory] Disconnecting database connections..."
        ActiveRecord::Base.connection_pool.disconnect!
        sleep(0.5)
        puts "[Memory] Reconnecting database..."
        ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute("SELECT 1") }
      rescue => e
        puts "[Memory] Error during database reconnection: #{e.message}"
      end
    end
    
    sleep(2.0) # Give GC more time to work
    
    # Return current memory usage after cleanup
    current_memory = mb
    puts "[Memory] After aggressive cleanup: #{current_memory.round(1)}MB"
    current_memory
  end
  
  def emergency_memory_cleanup
    puts "[Memory] Performing emergency memory cleanup..."
    
    # Force multiple aggressive GC cycles
    7.times do |i|  # Increased from 5 to 7 cycles
      puts "[Memory] Running emergency GC cycle #{i+1}/7..."
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.5)  # Longer sleep between cycles
    end
    
    # Compact the heap if supported
    compact_heap
    
    # Clear Ruby's object space
    if defined?(ObjectSpace) && ObjectSpace.respond_to?(:garbage_collect)
      ObjectSpace.garbage_collect
    end
    
    # Clear any temporary variables in the current scope
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.respond_to?(:clear_query_cache)
      ActiveRecord::Base.connection.clear_query_cache
    end
    
    # Reset database connections
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.respond_to?(:disconnect!)
      puts "[Memory] Disconnecting database connections..."
      ActiveRecord::Base.connection_pool.disconnect!
      sleep(1.0)
      
      # Try to reconnect to ensure we have a working connection
      begin
        puts "[Memory] Reconnecting database..."
        ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute("SELECT 1") }
      rescue => e
        puts "[Memory] Error during database reconnection: #{e.message}"
      end
    end
    
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.respond_to?(:clear_reloadable_connections!)
      ActiveRecord::Base.connection_pool.clear_reloadable_connections!
    end
    
    # Try to release memory back to the OS
    if RUBY_PLATFORM =~ /linux/
      # On Linux, we can try to release memory back to the OS
      begin
        File.write('/proc/self/oom_score_adj', '1000')
      rescue => e
        puts "[Memory] Failed to adjust OOM score: #{e.message}"
      end
    end
    
    # Log memory after cleanup
    current_memory = mb
    puts "[Memory] After emergency cleanup: #{current_memory.round(1)}MB"
    
    current_memory
  end
  
  def log_memory_status(context)
    puts "[Memory][#{context}] Current: #{mb.round(1)}MB, Threshold: #{@memory_threshold}MB, Batch size: #{@batch_size}, Processing batch size: #{@processing_batch_size}"
  end
  
  # Class method for easy access to aggressive memory cleanup
  def self.aggressive_memory_cleanup
    monitor = new
    monitor.aggressive_memory_cleanup
  end
end 
