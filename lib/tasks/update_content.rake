require_relative 'tmdb_tasks'
require 'get_process_mem'

namespace :tmdb do
  desc 'Update existing content from TMDb'
  task update_content: :environment do
    start_time = Time.now
    puts "Starting content update at #{start_time}"
    
    # Memory monitoring setup
    memory_monitor = GetProcessMem.new
    memory_threshold = ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    
    # Initialize with conservative batch sizes
    max_batch_size = ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = 10
    
    # Get job ID from environment variable if available (set by FetchContentJob)
    job_id = ENV['CURRENT_JOB_ID']
    
    begin
      # Check for cancellation before starting
      if job_cancelled?(job_id)
        puts "[Update Content] Job was cancelled before starting"
        return
      end
      
      last_update = Content.maximum(:tmdb_last_update) || 1.week.ago
      puts "Fetching changes since #{last_update}"

      # These return arrays of [id, type] pairs
      changes_data = TmdbService.fetch_movie_changes(last_update) + TmdbService.fetch_tv_changes(last_update)
      
      # Split into movie and TV show changes
      updated_movie_ids = changes_data.select { |_, type| type == 'movie' }.map { |id, _| id }
      updated_tv_ids = changes_data.select { |_, type| type == 'tv' }.map { |id, _| id }

      total_updates = updated_movie_ids.size + updated_tv_ids.size
      puts "Found #{updated_movie_ids.size} movie updates and #{updated_tv_ids.size} TV show updates"

      # Check memory before processing
      current_memory = memory_monitor.mb
      if current_memory > memory_threshold * 0.8
        puts "[Memory] Usage: #{current_memory.round(1)}MB before processing updates. Running GC..."
        GC.start(full_mark: true, immediate_sweep: true)
      end

      # Create items array in chunks to avoid large memory allocation
      items = []
      processed_count = 0
      
      # Process movies
      if updated_movie_ids.any?
        puts "Processing movie updates..."
        
        # Check for cancellation before processing movies
        if job_cancelled?(job_id)
          puts "[Update Content] Job was cancelled before processing movies"
          return
        end
        
        updated_movie_ids.each_slice(100) do |movie_ids_chunk|
          # Check for cancellation before processing each chunk
          if job_cancelled?(job_id)
            puts "[Update Content] Job was cancelled during movie processing"
            return
          end
          
          chunk_items = movie_ids_chunk.map { |id| { 'id' => id, 'type' => 'movie' } }
          items.concat(chunk_items)
          
          # Process this chunk if we have enough items
          if items.size >= batch_size
            processed_count += process_update_chunk(items, memory_monitor, memory_threshold, updated_movie_ids.size, updated_tv_ids.size, batch_size, processing_batch_size, max_batch_size, min_batch_size, start_time, processed_count, total_updates)
            items = [] # Clear the processed items
          end
        end
      end
      
      # Process TV shows
      if updated_tv_ids.any?
        puts "Processing TV show updates..."
        updated_tv_ids.each_slice(100) do |tv_ids_chunk|
          chunk_items = tv_ids_chunk.map { |id| { 'id' => id, 'type' => 'tv' } }
          items.concat(chunk_items)
          
          # Process this chunk if we have enough items
          if items.size >= batch_size
            processed_count += process_update_chunk(items, memory_monitor, memory_threshold, updated_movie_ids.size, updated_tv_ids.size, batch_size, processing_batch_size, max_batch_size, min_batch_size, start_time, processed_count, total_updates)
            items = [] # Clear the processed items
          end
        end
      end
      
      # Process any remaining items
      if items.any?
        processed_count += process_update_chunk(items, memory_monitor, memory_threshold, updated_movie_ids.size, updated_tv_ids.size, batch_size, processing_batch_size, max_batch_size, min_batch_size, start_time, processed_count, total_updates)
      end

      puts "Content update completed. Total items processed: #{processed_count}/#{total_updates}"
    rescue => e
      puts "Error during content update: #{e.message}"
      puts e.backtrace.take(10)
      GC.start(full_mark: true, immediate_sweep: true)
    ensure
      end_time = Time.now
      duration = (end_time - start_time).round(2)
      puts "Content update task ended at #{end_time}. Total duration: #{duration} seconds"
    end
  end
  
  private
  
  def process_update_chunk(items, memory_monitor, memory_threshold, movie_count, tv_count, initial_batch_size, initial_processing_batch_size, max_batch_size, min_batch_size, start_time, processed_so_far, total_items)
    return 0 if items.empty?
    
    # Use the passed batch sizes
    batch_size = initial_batch_size
    processing_batch_size = initial_processing_batch_size
    chunk_size = items.size
    
    # Track memory trend
    memory_readings = []
    critical_memory_threshold = memory_threshold * 1.2  # 20% above threshold for critical situations
    warning_memory_threshold = memory_threshold * 0.9   # Start reducing at 90% of threshold
    
    TmdbTasks.process_content_in_batches(items, batch_size: batch_size, processing_batch_size: processing_batch_size) do |processed_items, batch_total|
      # Calculate overall progress including previously processed items
      overall_processed = processed_so_far + processed_items
      progress_percent = (overall_processed.to_f / total_items * 100).round(2)
      current_memory = memory_monitor.mb
      
      # Track memory trend (keep last 5 readings)
      memory_readings << current_memory
      memory_readings.shift if memory_readings.size > 5
      memory_trend_increasing = memory_readings.size >= 3 && memory_readings[-1] > memory_readings[-3]
      
      # Calculate elapsed time and ETA
      elapsed = Time.now - start_time
      eta = overall_processed > 0 ? (elapsed / overall_processed * (total_items - overall_processed)).round(2) : nil
      
      # Dynamically adjust batch sizes based on memory usage
      if current_memory > critical_memory_threshold
        # Critical memory situation - reduce batch size drastically and force GC
        old_batch_size = batch_size
        batch_size = [(batch_size * 0.5).to_i, min_batch_size].max
        processing_batch_size = [(processing_batch_size * 0.5).to_i, min_batch_size].max
        puts "[Memory] CRITICAL: #{current_memory.round(1)}MB exceeds threshold by 20%. Reducing batch size from #{old_batch_size} to #{batch_size}"
        GC.start(full_mark: true, immediate_sweep: true)
        sleep(1.0) # Pause to allow GC to complete
      elsif current_memory > memory_threshold
        # Above threshold - reduce batch size and force GC
        old_batch_size = batch_size
        batch_size = [(batch_size * 0.7).to_i, min_batch_size].max
        processing_batch_size = [(processing_batch_size * 0.7).to_i, min_batch_size].max
        puts "[Memory] HIGH: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{batch_size}"
        GC.start(full_mark: true, immediate_sweep: true)
        sleep(0.5) # Short pause to allow GC to complete
      elsif current_memory > warning_memory_threshold || memory_trend_increasing
        # Approaching threshold or trending up - reduce batch size moderately
        old_batch_size = batch_size
        batch_size = [(batch_size * 0.8).to_i, min_batch_size].max
        processing_batch_size = [(processing_batch_size * 0.8).to_i, min_batch_size].max
        puts "[Memory] WARNING: #{current_memory.round(1)}MB approaching threshold or trending up. Reducing batch size from #{old_batch_size} to #{batch_size}"
        GC.start(full_mark: true, immediate_sweep: true)
      elsif current_memory < memory_threshold * 0.7 && batch_size < max_batch_size
        # If memory usage is low, gradually increase batch size
        old_batch_size = batch_size
        batch_size = [(batch_size * 1.25).to_i, max_batch_size].min
        processing_batch_size = [(processing_batch_size * 1.25).to_i, (max_batch_size / 3).to_i].min
        puts "[Memory] LOW: #{current_memory.round(1)}MB. Increasing batch size from #{old_batch_size} to #{batch_size}"
      end
      
      puts "[Update Content] Overall: #{overall_processed}/#{total_items} (#{progress_percent}%)" \
           "\n  Current chunk: #{processed_items}/#{batch_total}" \
           "\n  Movies: #{movie_count}, TV Shows: #{tv_count}" \
           "\n  Elapsed: #{elapsed.round(2)}s" \
           "\n  ETA: #{eta ? "#{eta}s" : "calculating..."}" \
           "\n  Memory: #{current_memory.round(1)}MB" \
           "\n  Batch size: #{batch_size}"
    end
    
    # Force GC if memory usage is high
    current_memory = memory_monitor.mb
    if current_memory > memory_threshold * 0.8
      puts "[Memory] Usage: #{current_memory.round(1)}MB after processing chunk. Running GC..."
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(0.5) # Give GC time to work
    end
    
    # Return the number of items processed in this chunk
    return chunk_size
  end
end
