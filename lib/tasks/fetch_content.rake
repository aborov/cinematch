require_relative 'tmdb_tasks'
require 'parallel'
require 'get_process_mem'

namespace :tmdb do
  desc 'Fetch new content and update existing content from TMDb'
  task fetch_content: :environment do
    start_time = Time.now
    puts "Starting to fetch content at #{start_time}"

    # Get job ID for cancellation checks
    job_id = ENV['CURRENT_JOB_ID']
    
    # Check if job was cancelled before starting
    if job_id && job_cancelled?(job_id)
      puts "Job #{job_id} was cancelled before starting. Exiting."
      return
    end

    # Memory monitoring setup
    memory_monitor = GetProcessMem.new
    memory_threshold = ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    
    # Initialize with conservative batch sizes
    max_batch_size = ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = 10
    
    genres = fetch_and_store_genres

    # Define sources as separate tasks that can be run independently
    sources = [
      { name: 'Movies by categories', task: 'tmdb:fetch_movies_by_categories' },
      { name: 'TV shows by categories', task: 'tmdb:fetch_tv_shows_by_categories' },
      { name: 'Content by genres', task: 'tmdb:fetch_content_by_genres', args: [genres] },
      { name: 'Content by decades', task: 'tmdb:fetch_content_by_decades' },
      { name: 'Content by keywords', task: 'tmdb:fetch_content_by_keywords' },
      { name: 'Content by language', task: 'tmdb:fetch_content_by_language' }
    ]

    total_fetchers = sources.size
    puts "Starting to fetch content from #{total_fetchers} sources..."

    sources.each_with_index do |source_info, index|
      begin
        # Check for cancellation before processing each source
        if job_id && job_cancelled?(job_id)
          puts "Job #{job_id} was cancelled. Stopping content fetch."
          break
        end
        
        puts "Fetching from source #{index + 1} of #{total_fetchers}: #{source_info[:name]}..."
        
        # Check memory before fetching
        current_memory = memory_monitor.mb
        if current_memory > memory_threshold
          puts "[Memory] High usage (#{current_memory.round(1)}MB) before fetching #{source_info[:name]}. Running GC..."
          GC.start(full_mark: true, immediate_sweep: true)
          sleep(1.0) # Give GC time to work
        end
        
        # Run the source-specific task with the current memory parameters
        args = source_info[:args] || []
        Rake::Task[source_info[:task]].reenable
        # Pass job_id to the task for cancellation checks
        Rake::Task[source_info[:task]].invoke(*args, memory_threshold, max_batch_size, batch_size, processing_batch_size, min_batch_size, start_time, job_id)
        
        # Force aggressive memory cleanup after each source
        GC.start(full_mark: true, immediate_sweep: true)
        sleep(2.0) # Give GC more time to work between sources
        
        # Clear Ruby's object space to help with memory release
        if defined?(ObjectSpace) && ObjectSpace.respond_to?(:garbage_collect)
          ObjectSpace.garbage_collect
        end
        
        # Log memory after cleanup
        puts "[Memory] After source #{source_info[:name]}: #{memory_monitor.mb.round(1)}MB"
      rescue StandardError => e
        puts "[Error][#{source_info[:name]}] #{e.message}"
        puts e.backtrace.take(10)
        GC.start(full_mark: true, immediate_sweep: true)
        # Continue with next source instead of failing the entire task
      end
    end

    end_time = Time.now
    puts "All content has been fetched and processed at #{end_time}. Total duration: #{(end_time - start_time).round(2)} seconds"
  end

  # Helper method to process content with memory management
  def process_content_with_memory_management(items, source_name, content_type, memory_monitor, memory_threshold, initial_batch_size, initial_processing_batch_size, max_batch_size, min_batch_size, start_time, job_id = nil, max_chunk_size = 100)
    batch_size = initial_batch_size
    processing_batch_size = initial_processing_batch_size
    total_items = items.size
    
    # Check for cancellation before starting
    if job_id && job_cancelled?(job_id)
      puts "Job #{job_id} was cancelled. Skipping processing for #{source_name}."
      return 0
    end
    
    # Track memory trend
    memory_readings = []
    critical_memory_threshold = memory_threshold * 1.1  # 10% above threshold for critical situations
    warning_memory_threshold = memory_threshold * 0.8   # Start reducing at 80% of threshold
    emergency_threshold = memory_threshold * 1.3        # Emergency threshold at 30% above
    
    # Track consecutive high memory readings
    consecutive_high_readings = 0
    
    # Track when to perform periodic cleanup
    items_since_cleanup = 0
    cleanup_interval = 300  # Perform cleanup every 300 items (reduced from 500)
    
    # Track pauses due to high memory
    last_pause_time = nil
    pause_interval = 30  # Minimum seconds between pauses
    
    # Track object allocations
    last_object_count = ObjectSpace.count_objects[:TOTAL] rescue 0
    
    # Add job cancellation check method
    def job_cancelled?(job_id)
      return false unless job_id
      
      # Check if JobCancellationService exists and use it
      if defined?(JobCancellationService) && JobCancellationService.respond_to?(:cancelled?)
        JobCancellationService.cancelled?(job_id)
      else
        # Fallback to checking GoodJob directly if service doesn't exist
        GoodJob::Job.where(id: job_id).first&.cancelled?
      end
    rescue => e
      puts "Error checking job cancellation status: #{e.message}"
      false
    end
    
    # Process items in smaller chunks
    items.each_slice(max_chunk_size).with_index do |chunk_items, chunk_index|
      # Check for cancellation before processing each chunk
      if job_id && job_cancelled?(job_id)
        puts "Job #{job_id} was cancelled. Stopping processing at chunk #{chunk_index+1}."
        break
      end
      
      chunk_start = chunk_index * max_chunk_size
      chunk_end = [chunk_start + max_chunk_size, total_items].min
      
      puts "Processing items #{chunk_start+1}-#{chunk_end} of #{total_items} (chunk #{chunk_index+1}/#{(total_items.to_f / max_chunk_size).ceil})"
      
      # Force GC between chunks
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(0.5)
      
      TmdbTasks.process_content_in_batches(chunk_items, batch_size: batch_size, processing_batch_size: processing_batch_size) do |processed_items, batch_total|
        # Check for cancellation periodically during batch processing
        if job_id && processed_items % 50 == 0 && job_cancelled?(job_id)
          puts "Job #{job_id} was cancelled during batch processing. Stopping."
          raise "Job cancelled" # This will be caught by the rescue in process_content_in_batches
        end
        
        # Adjust processed_items to account for the current chunk
        total_processed = chunk_start + processed_items
        progress_percent = (total_processed.to_f / total_items * 100).round(2)
        current_memory = memory_monitor.mb
        
        # Track memory trend (keep last 10 readings)
        memory_readings << current_memory
        memory_readings.shift if memory_readings.size > 10
        memory_trend_increasing = memory_readings.size >= 3 && 
                                memory_readings[-1] > memory_readings[-2] && 
                                memory_readings[-2] > memory_readings[-3]
        
        # Update consecutive high readings counter
        if current_memory > memory_threshold
          consecutive_high_readings += 1
        else
          consecutive_high_readings = 0
        end
        
        # Calculate elapsed time and ETA
        elapsed = Time.now - start_time
        eta = total_processed > 0 ? (elapsed / total_processed * (total_items - total_processed)).round(2) : nil
        
        # Check object allocations
        current_object_count = ObjectSpace.count_objects[:TOTAL] rescue 0
        object_growth = current_object_count - last_object_count
        if object_growth > 100000  # If we've allocated more than 100k objects since last check
          puts "[Memory] High object allocation detected: #{object_growth} new objects. Forcing GC..."
          GC.start(full_mark: true, immediate_sweep: true)
          last_object_count = ObjectSpace.count_objects[:TOTAL] rescue 0
        end
        
        # Periodic forced cleanup
        items_since_cleanup += batch_total
        if items_since_cleanup >= cleanup_interval
          puts "[Memory] Performing periodic cleanup after processing #{items_since_cleanup} items"
          3.times do  # More aggressive cleanup
            GC.start(full_mark: true, immediate_sweep: true)
            sleep(0.3)
          end
          
          # Try to compact heap if supported
          GC.compact if GC.respond_to?(:compact)
          
          items_since_cleanup = 0
          last_object_count = ObjectSpace.count_objects[:TOTAL] rescue 0
        end
        
        # Emergency situation - memory keeps growing despite previous reductions
        if (current_memory > emergency_threshold) || 
          (consecutive_high_readings >= 5 && memory_trend_increasing) ||
          (current_memory > critical_memory_threshold && batch_size <= min_batch_size * 2)
          
          # Only pause once every pause_interval seconds
          if last_pause_time.nil? || (Time.now - last_pause_time) > pause_interval
            puts "[Memory] EMERGENCY: #{current_memory.round(1)}MB. Memory continues to grow despite batch size reductions."
            puts "[Memory] Pausing processing for 10 seconds to allow memory to stabilize..."
            
            # Force aggressive memory cleanup
            5.times do
              GC.start(full_mark: true, immediate_sweep: true)
              sleep(1.0)
            end
            
            # Try to compact heap if supported
            GC.compact if GC.respond_to?(:compact)
            
            # Clear any temporary variables in the current scope
            if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.respond_to?(:clear_query_cache)
              ActiveRecord::Base.connection.clear_query_cache
            end
            
            # Try to release memory back to the OS on Linux
            if RUBY_PLATFORM =~ /linux/
              begin
                File.write('/proc/self/oom_score_adj', '1000')
              rescue => e
                puts "[Memory] Failed to adjust OOM score: #{e.message}"
              end
            end
            
            sleep(5.0)  # Additional pause to allow memory to stabilize
            last_pause_time = Time.now
            
            # Set batch size to absolute minimum
            batch_size = min_batch_size
            processing_batch_size = min_batch_size
            
            puts "[Memory] After emergency cleanup: #{memory_monitor.mb.round(1)}MB"
            puts "[Memory] Batch size reduced to minimum #{batch_size}"
            
            # Reset object count after emergency cleanup
            last_object_count = ObjectSpace.count_objects[:TOTAL] rescue 0
          end
        end
        
        # Dynamically adjust batch sizes based on memory usage
        if current_memory > critical_memory_threshold
          # Critical memory situation - reduce batch size drastically and force GC
          old_batch_size = batch_size
          batch_size = [(batch_size * 0.4).to_i, min_batch_size].max
          processing_batch_size = [(processing_batch_size * 0.4).to_i, min_batch_size].max
          puts "[Memory] CRITICAL: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{batch_size}"
          GC.start(full_mark: true, immediate_sweep: true)
          sleep(2.0) # Longer pause to allow GC to complete
        elsif current_memory > memory_threshold
          # Above threshold - reduce batch size and force GC
          old_batch_size = batch_size
          batch_size = [(batch_size * 0.6).to_i, min_batch_size].max
          processing_batch_size = [(processing_batch_size * 0.6).to_i, min_batch_size].max
          puts "[Memory] HIGH: #{current_memory.round(1)}MB exceeds threshold. Reducing batch size from #{old_batch_size} to #{batch_size}"
          GC.start(full_mark: true, immediate_sweep: true)
          sleep(1.0) # Longer pause to allow GC to complete
        elsif current_memory > warning_memory_threshold || memory_trend_increasing
          # Approaching threshold or trending up - reduce batch size moderately
          old_batch_size = batch_size
          batch_size = [(batch_size * 0.7).to_i, min_batch_size].max
          processing_batch_size = [(processing_batch_size * 0.7).to_i, min_batch_size].max
          puts "[Memory] WARNING: #{current_memory.round(1)}MB approaching threshold or trending up. Reducing batch size from #{old_batch_size} to #{batch_size}"
          GC.start(full_mark: true, immediate_sweep: true)
          sleep(0.5) # Brief pause to allow GC to complete
        elsif current_memory < memory_threshold * 0.6 && batch_size < max_batch_size
          # If memory usage is low, gradually increase batch size
          old_batch_size = batch_size
          batch_size = [(batch_size * 1.15).to_i, max_batch_size].min
          processing_batch_size = [(processing_batch_size * 1.15).to_i, (max_batch_size / 3).to_i].min
          puts "[Memory] LOW: #{current_memory.round(1)}MB. Increasing batch size from #{old_batch_size} to #{batch_size}"
        end
        
        puts "[Fetch Content][#{source_name}] #{content_type}: #{total_processed}/#{total_items} (#{progress_percent}%)" \
            "\n  Valid: #{total_processed}, Skipped: #{total_items - total_processed}" \
            "\n  Elapsed: #{elapsed.round(2)}s" \
            "\n  ETA: #{eta ? "#{eta}s" : "calculating..."}" \
            "\n  Memory: #{current_memory.round(1)}MB" \
            "\n  Batch size: #{batch_size}, Processing batch size: #{processing_batch_size}"
      end
      
      # Clear chunk_items to help GC
      chunk_items = nil
    end
  end

  def fetch_and_store_genres
    genres = TmdbService.fetch_genres[:all_genres]
    puts "Fetched #{genres.size} genres from TMDb"
    
    ActiveRecord::Base.transaction do
      result = Genre.upsert_all(
        genres.map { |genre| { tmdb_id: genre['id'], name: genre['name'] } },
        unique_by: :tmdb_id
      )
      puts "Inserted/Updated #{result.length} genres in the database"
    end
    
    puts 'Genres have been fetched and stored successfully.'
    genres
  end

  # Create separate tasks for each source
  desc 'Fetch movies by categories'
  task :fetch_movies_by_categories, [:memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || ENV.fetch('MIN_BATCH_SIZE', 2).to_i  # Lower minimum batch size
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    # Check memory before starting
    current_memory = memory_monitor.mb
    if current_memory > memory_threshold * 0.8
      puts "[Memory] High usage (#{current_memory.round(1)}MB) before starting. Running aggressive cleanup..."
      3.times do
        GC.start(full_mark: true, immediate_sweep: true)
        sleep(0.5)
      end
      puts "[Memory] After cleanup: #{memory_monitor.mb.round(1)}MB"
    end
    
    categories = {
      'popular' => 30,      # 600 items
      'top_rated' => 30,    # 600 items
      'now_playing' => 15,  # 300 items
      'upcoming' => 15      # 300 items
    }
    
    # Process each category separately to avoid building a large array
    total_items = 0
    skipped_items = 0
    
    categories.each do |category, pages|
      puts "Fetching movies from category: #{category} (#{pages} pages)"
      
      # Fetch and process in smaller chunks to avoid memory buildup
      (1..pages).each_slice(5) do |page_chunk|
        # Force GC between chunks
        GC.start(full_mark: true, immediate_sweep: true)
        
        # Fetch a smaller chunk of pages (5 pages at a time)
        chunk_pages = page_chunk.size
        items = TmdbService.fetch_movies_by_category(category, chunk_pages)
        
        chunk_size = items.size
        total_items += chunk_size
        
        puts "Processing #{chunk_size} movies from #{category} (pages #{page_chunk.first}-#{page_chunk.last})"
        
        # Process this chunk with memory management
        process_content_with_memory_management(
          items, 
          "Movies by categories (#{category})", 
          "Movies", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear items array to help GC
        items = nil
        GC.start(full_mark: true, immediate_sweep: true)
        sleep(1.0) # Give GC time to work
      end
    end
    
    puts "Processed a total of #{total_items} movies from categories (#{skipped_items} skipped)"
    
    # Final cleanup
    GC.start(full_mark: true, immediate_sweep: true)
  end

  desc 'Fetch TV shows by categories'
  task :fetch_tv_shows_by_categories, [:memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || 10
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    categories = {
      'popular' => 30,        # 600 items
      'top_rated' => 30,      # 600 items
      'on_the_air' => 15,     # 300 items
      'airing_today' => 15    # 300 items
    }
    
    items = categories.flat_map do |category, pages|
      TmdbService.fetch_tv_shows_by_category(category, pages)
    end
    
    puts "Found #{items.size} TV shows from categories"
    
    # Process TV shows with dynamic batch size adjustment
    process_content_with_memory_management(
      items, 
      "TV shows by categories", 
      "TV Shows", 
      memory_monitor, 
      memory_threshold,
      batch_size,
      processing_batch_size,
      max_batch_size,
      min_batch_size,
      start_time
    )
    
    # Clear items array to help GC
    items = nil
    GC.start(full_mark: true, immediate_sweep: true)
  end

  desc 'Fetch content by genres'
  task :fetch_content_by_genres, [:genres, :memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || 10
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    # If genres not passed, fetch them
    genres = args[:genres] || fetch_and_store_genres
    
    # Process genres in smaller chunks to avoid memory issues
    genre_chunk_size = 5
    genres.each_slice(genre_chunk_size) do |genre_chunk|
      puts "Processing #{genre_chunk.size} genres..."
      
      # Fetch movies and TV shows for this genre chunk
      items = genre_chunk.flat_map do |genre|
        movies = TmdbService.fetch_by_genre(genre['id'], 'movie')
        tv_shows = TmdbService.fetch_by_genre(genre['id'], 'tv')
        
        # Process each type separately to avoid building a large array
        process_content_with_memory_management(
          movies, 
          "Content by genres (#{genre['name']} - Movies)", 
          "Movies", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear movies array to help GC
        movies_count = movies.size
        movies = nil
        GC.start(full_mark: true, immediate_sweep: true)
        
        process_content_with_memory_management(
          tv_shows, 
          "Content by genres (#{genre['name']} - TV Shows)", 
          "TV Shows", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear tv_shows array to help GC
        tv_shows_count = tv_shows.size
        tv_shows = nil
        GC.start(full_mark: true, immediate_sweep: true)
        
        puts "Processed #{movies_count} movies and #{tv_shows_count} TV shows for genre #{genre['name']}"
        
        # Return empty array since we've already processed the items
        []
      end
      
      # Force GC after each genre chunk
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0) # Give GC time to work
    end
  end

  desc 'Fetch content by decades'
  task :fetch_content_by_decades, [:memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || 10
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    decades = {
      1950 => 10,
      1960 => 10,
      1970 => 15,
      1980 => 20,
      1990 => 25,
      2000 => 30,
      2010 => 35,
      2020 => 20
    }
    
    # Process each decade separately to avoid memory issues
    decades.each do |decade, pages|
      puts "Processing decade #{decade}s..."
      
      ['movie', 'tv'].each do |type|
        items = TmdbService.fetch_by_decade(decade, decade + 9, type, pages)
        
        process_content_with_memory_management(
          items, 
          "Content by decades (#{decade}s - #{type == 'movie' ? 'Movies' : 'TV Shows'})", 
          type == 'movie' ? "Movies" : "TV Shows", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear items array to help GC
        items = nil
        GC.start(full_mark: true, immediate_sweep: true)
      end
      
      # Force GC after each decade
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0) # Give GC time to work
    end
  end

  desc 'Fetch content by keywords'
  task :fetch_content_by_keywords, [:memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || 10
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    popular_keywords = [
      'cyberpunk', 'post-apocalyptic', 'dystopia', 'time-travel',
      'supernatural', 'psychological', 'film-noir', 'steampunk',
      'martial-arts', 'biography', 'historical', 'musical'
    ]
    
    # Process each keyword separately to avoid memory issues
    popular_keywords.each do |keyword|
      puts "Processing keyword #{keyword}..."
      
      ['movie', 'tv'].each do |type|
        items = TmdbService.fetch_by_keyword(keyword, type, 10)
        
        process_content_with_memory_management(
          items, 
          "Content by keywords (#{keyword} - #{type == 'movie' ? 'Movies' : 'TV Shows'})", 
          type == 'movie' ? "Movies" : "TV Shows", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear items array to help GC
        items = nil
        GC.start(full_mark: true, immediate_sweep: true)
      end
      
      # Force GC after each keyword
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0) # Give GC time to work
    end
  end

  desc 'Fetch content by language'
  task :fetch_content_by_language, [:memory_threshold, :max_batch_size, :batch_size, :processing_batch_size, :min_batch_size, :start_time] => :environment do |t, args|
    memory_threshold = args[:memory_threshold]&.to_i || ENV.fetch('MEMORY_THRESHOLD_MB', 400).to_i
    max_batch_size = args[:max_batch_size]&.to_i || ENV.fetch('MAX_BATCH_SIZE', 100).to_i
    batch_size = args[:batch_size]&.to_i || ENV.fetch('BATCH_SIZE', 30).to_i
    processing_batch_size = args[:processing_batch_size]&.to_i || ENV.fetch('PROCESSING_BATCH_SIZE', 10).to_i
    min_batch_size = args[:min_batch_size]&.to_i || 10
    start_time = args[:start_time] || Time.now
    
    memory_monitor = GetProcessMem.new
    
    languages = {
      'ja' => 25,  # Japanese
      'ko' => 25,  # Korean
      'hi' => 20,  # Hindi
      'fr' => 15,  # French
      'es' => 15,  # Spanish
      'de' => 15,  # German
      'it' => 15,  # Italian
      'zh' => 15,  # Chinese
      'ru' => 15,  # Russian
      'pt' => 15,  # Portuguese
      'tr' => 10,  # Turkish
      'th' => 10   # Thai
    }
    
    # Process each language separately to avoid memory issues
    languages.each do |lang, pages|
      puts "Processing language #{lang}..."
      
      ['movie', 'tv'].each do |type|
        items = TmdbService.fetch_by_language(lang, type, pages)
        
        process_content_with_memory_management(
          items, 
          "Content by language (#{lang} - #{type == 'movie' ? 'Movies' : 'TV Shows'})", 
          type == 'movie' ? "Movies" : "TV Shows", 
          memory_monitor, 
          memory_threshold,
          batch_size,
          processing_batch_size,
          max_batch_size,
          min_batch_size,
          start_time
        )
        
        # Clear items array to help GC
        items = nil
        GC.start(full_mark: true, immediate_sweep: true)
      end
      
      # Force GC after each language
      GC.start(full_mark: true, immediate_sweep: true)
      sleep(1.0) # Give GC time to work
    end
  end
end
