require_relative 'tmdb_tasks'
require 'get_process_mem'

namespace :tmdb do
  desc "Fill in missing details for movies and TV shows"
  task fill_missing_details: :environment do
    start_time = Time.now
    memory_monitor = MemoryMonitor.new
    
    # Get environment variables or use defaults
    memory_threshold_mb = (ENV['MEMORY_THRESHOLD_MB'] || 400).to_i
    max_batch_size = (ENV['MAX_BATCH_SIZE'] || 100).to_i
    batch_size = (ENV['BATCH_SIZE'] || 30).to_i
    min_batch_size = (ENV['MIN_BATCH_SIZE'] || 5).to_i
    
    # Get job ID from environment variable if available (set by FetchContentJob)
    job_id = ENV['CURRENT_JOB_ID']
    
    puts "[Fill Missing Details] Starting at #{start_time}"
    puts "[Fill Missing Details] Memory threshold: #{memory_threshold_mb}MB, Initial batch size: #{batch_size}, Max batch size: #{max_batch_size}"
    
    # Find all movies and TV shows with missing details
    movies_missing_details = Content.where(content_type: 'movie')
                                   .where(runtime: nil)
                                   .or(Content.where(content_type: 'movie', tagline: nil))
                                   .or(Content.where(content_type: 'movie', trailer_url: nil))
    
    tv_shows_missing_details = Content.where(content_type: 'tv')
                                     .where(number_of_seasons: nil)
                                     .or(Content.where(content_type: 'tv', number_of_episodes: nil))
                                     .or(Content.where(content_type: 'tv', trailer_url: nil))
    
    total_items = movies_missing_details.count + tv_shows_missing_details.count
    puts "[Fill Missing Details] Found #{movies_missing_details.count} movies and #{tv_shows_missing_details.count} TV shows with missing details (total: #{total_items})"
    
    # Process in chunks to manage memory
    processed_so_far = 0
    
    # Check for cancellation
    if job_cancelled?(job_id)
      puts "[Fill Missing Details] Job was cancelled before processing"
      return
    end
    
    # Process movies with missing details
    if movies_missing_details.any?
      puts "[Fill Missing Details] Processing #{movies_missing_details.count} movies with missing details"
      
      # Process in chunks of 1000 to avoid loading too many records at once
      movies_missing_details.find_in_batches(batch_size: 100) do |chunk|
        # Check for cancellation before processing each chunk
        if job_cancelled?(job_id)
          puts "[Fill Missing Details] Job was cancelled during processing"
          return
        end
        
        processed_items = process_missing_details_chunk(
          chunk, 
          memory_monitor, 
          memory_threshold_mb, 
          batch_size, 
          max_batch_size, 
          min_batch_size, 
          start_time, 
          processed_so_far, 
          total_items,
          job_id
        )
        processed_so_far += processed_items
      end
    end
    
    # Check for cancellation between movie and TV show processing
    if job_cancelled?(job_id)
      puts "[Fill Missing Details] Job was cancelled after processing movies"
      return
    end
    
    # Process TV shows with missing details
    if tv_shows_missing_details.any?
      puts "[Fill Missing Details] Processing #{tv_shows_missing_details.count} TV shows with missing details"
      
      # Process in chunks of 1000 to avoid loading too many records at once
      tv_shows_missing_details.find_in_batches(batch_size: 100) do |chunk|
        # Check for cancellation before processing each chunk
        if job_cancelled?(job_id)
          puts "[Fill Missing Details] Job was cancelled during processing"
          return
        end
        
        processed_items = process_missing_details_chunk(
          chunk, 
          memory_monitor, 
          memory_threshold_mb, 
          batch_size, 
          max_batch_size, 
          min_batch_size, 
          start_time, 
          processed_so_far, 
          total_items,
          job_id
        )
        processed_so_far += processed_items
      end
    end
    
    end_time = Time.now
    duration = (end_time - start_time).round(2)
    puts "[Fill Missing Details] Completed at #{end_time}"
    puts "[Fill Missing Details] Duration: #{duration}s"
    puts "[Fill Missing Details] Final memory usage: #{memory_monitor.mb.round(1)}MB"
  end
end

def job_cancelled?(job_id)
  return false if job_id.nil?
  
  # Use JobCancellationService to check if the job has been cancelled
  cancelled = JobCancellationService.cancelled?(job_id)
  Rails.logger.info "Job #{job_id} cancellation check in rake task: #{cancelled}" if cancelled
  cancelled
end

def fetch_trailer_url(videos)
  return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
  trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' } ||
            videos.find { |v| v['type'] == 'Teaser' && v['site'] == 'YouTube' }
  trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
end

def process_missing_details_chunk(items, memory_monitor, memory_threshold, initial_batch_size, max_batch_size, min_batch_size, start_time, processed_so_far, total_items, job_id = nil)
  return 0 if items.empty?
  
  # Use the passed batch size
  batch_size = initial_batch_size
  chunk_size = items.size
  
  # Track memory trend
  memory_readings = []
  critical_memory_threshold = memory_threshold * 1.2  # 20% above threshold for critical situations
  warning_memory_threshold = memory_threshold * 0.9   # Start reducing at 90% of threshold
  
  TmdbTasks.process_content_in_batches(items, batch_size: batch_size) do |processed_items, batch_total|
    # Check for cancellation before processing each batch
    if job_cancelled?(job_id)
      puts "[Fill Missing Details] Job was cancelled during batch processing"
      return 0
    end
    
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
      puts "[Memory] CRITICAL: #{current_memory.round(1)}MB exceeds threshold by 20%. Reducing batch size from #{old_batch_size} to #{batch_size}"
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0) # Pause to allow GC to complete
    elsif current_memory > memory_threshold
      # Above threshold - reduce batch size and force GC
      old_batch_size = batch_size
      batch_size = [(batch_size * 0.7).to_i, min_batch_size].max
      puts "[Memory] HIGH: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{batch_size}"
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(0.5) # Short pause to allow GC to complete
    elsif current_memory > warning_memory_threshold || memory_trend_increasing
      # Approaching threshold or trending up - reduce batch size moderately
      old_batch_size = batch_size
      batch_size = [(batch_size * 0.8).to_i, min_batch_size].max
      puts "[Memory] WARNING: #{current_memory.round(1)}MB approaching threshold or trending up. Reducing batch size from #{old_batch_size} to #{batch_size}"
      GC.start(full_mark: true, immediate_sweep: true)
    elsif current_memory < memory_threshold * 0.7 && batch_size < max_batch_size
      # If memory usage is low, gradually increase batch size
      old_batch_size = batch_size
      batch_size = [(batch_size * 1.25).to_i, max_batch_size].min
      puts "[Memory] LOW: #{current_memory.round(1)}MB. Increasing batch size from #{old_batch_size} to #{batch_size}"
    end
    
    puts "[Fill Missing Details] Overall: #{overall_processed}/#{total_items} (#{progress_percent}%)" \
         "\n  Current chunk: #{processed_items}/#{batch_total}" \
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
