module TmdbTasks
  def self.update_content_batch(content_list)
    puts "Processing #{content_list.size} items"
    
    return if content_list.empty?
    
    # Define ALL possible keys upfront
    all_keys = [
      :source_id, :source, :title, :description, :poster_url, :backdrop_url,
      :release_year, :content_type, :vote_average, :vote_count, :popularity,
      :original_language, :status, :tagline, :genre_ids, :production_countries,
      :directors, :cast, :trailer_url, :imdb_id, :adult, :spoken_languages,
      :runtime, :plot_keywords, :tv_show_type, :number_of_seasons,
      :number_of_episodes, :in_production, :creators, :tmdb_last_update
    ]

    # Get content types for each item
    source_ids = content_list.map { |item| item['id'].to_s }
    types = content_list.map { |item| item['type'] || (item['title'] ? 'movie' : 'tv') }
    
    # Fetch existing content matching both source_id AND content_type
    existing_contents = Content.where(source_id: source_ids)
                              .where(content_type: types)
                              .index_by { |c| [c.source_id, c.content_type] }
    
    content_attributes = []
    
    # Process each item individually to avoid building a large array in memory
    content_list.each do |item|
      type = item['type'] || (item['title'] ? 'movie' : 'tv')
      
      next if item['title'].blank? && item['name'].blank?

      # Start with a hash containing all keys set to nil
      attributes = all_keys.each_with_object({}) { |key, hash| hash[key] = nil }
      
      # Then fill in the values we have
      attributes.merge!(
        source_id: item['id'].to_s,
        source: 'tmdb',
        title: item['title'] || item['name'],
        description: item['overview'],
        poster_url: item['poster_path'] ? "https://image.tmdb.org/t/p/w500#{item['poster_path']}" : nil,
        backdrop_url: item['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{item['backdrop_path']}" : nil,
        release_year: parse_release_year(item['release_date'] || item['first_air_date']),
        content_type: type == 'movie' ? 'movie' : 'tv',
        vote_average: item['vote_average'],
        vote_count: item['vote_count'],
        popularity: item['popularity'],
        original_language: item['original_language'],
        status: item['status'],
        tagline: item['tagline'],
        genre_ids: item['genres']&.map { |g| g['id'] }&.join(',') || '',
        production_countries: item['production_countries']&.to_json || '[]',
        directors: item['credits']&.dig('crew')&.select { |c| c['job'] == 'Director' }&.map { |d| d['name'] }&.join(',') || '',
        cast: item['credits']&.dig('cast')&.take(5)&.map { |c| c['name'] }&.join(',') || '',
        trailer_url: fetch_trailer_url(item['videos']&.dig('results') || []),
        imdb_id: item['external_ids']&.dig('imdb_id') || item['imdb_id'],
        adult: item['adult'],
        spoken_languages: item['spoken_languages']&.to_json || '[]',
        # Initialize all type-specific attributes with defaults
        runtime: nil,
        plot_keywords: '',
        tv_show_type: nil,
        number_of_seasons: nil,
        number_of_episodes: nil,
        in_production: nil,
        creators: nil
      )

      # Fill in type-specific values
      if type == 'movie'
        attributes[:runtime] = item['runtime']
        attributes[:plot_keywords] = item['keywords']&.dig('keywords')&.map { |k| k['name'] }&.join(',') || ''
      else # TV show
        attributes[:runtime] = item['episode_run_time']&.first
        attributes[:plot_keywords] = item['keywords']&.dig('results')&.map { |k| k['name'] }&.join(',') || ''
        attributes[:tv_show_type] = item['type']
        attributes[:number_of_seasons] = item['number_of_seasons']
        attributes[:number_of_episodes] = item['number_of_episodes']
        attributes[:in_production] = item['in_production']
        attributes[:creators] = item['created_by']&.map { |c| c['name'] }&.join(',') || ''
      end

      # Check for changes using the pre-fetched content with both source_id and content_type
      existing_content = existing_contents[[item['id'].to_s, type]]
      if existing_content
        changed = content_changed?(existing_content, attributes, type)
        attributes[:tmdb_last_update] = Time.current if changed
      else
        attributes[:tmdb_last_update] = Time.current
      end

      content_attributes << attributes
    end

    puts "Found #{content_attributes.size} valid items"

    # Process in smaller batches to avoid memory spikes
    if content_attributes.any?
      content_attributes.each_slice(50) do |batch|
        # Remove duplicates based on source_id AND content_type within this batch
        unique_batch = batch.uniq { |item| [item[:source_id], item[:content_type]] }
        
        Content.upsert_all(
          unique_batch,
          unique_by: [:source_id, :content_type],  # Updated to use composite unique key
          update_only: unique_batch.first.keys - [:source_id, :source, :content_type]
        )
        
        # Help GC
        unique_batch = nil
        GC.start if GetProcessMem.new.mb > 400
      end
    else
      puts "No valid content attributes found to update."
    end
  end

  def self.parse_release_year(date_string)
    date_string.present? ? date_string.split('-').first.to_i : nil
  end

  def self.parse_tmdb_date(date_string)
    date_string.present? ? Time.parse(date_string) : nil
  rescue ArgumentError
    nil
  end

  def self.fetch_trailer_url(videos)
    return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
    trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' } ||
              videos.find { |v| v['type'] == 'Teaser' && v['site'] == 'YouTube' }
    trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
  end

  def self.process_content_in_batches(items, batch_size: 50, processing_batch_size: 20, min_batch_size: 10, min_processing_batch_size: 5, memory_threshold: 400, job_type: nil, &block)
    return if items.empty?
    
    memory_monitor = GetProcessMem.new
    total_items = items.size
    processed_items = 0
    updated_items = []
    
    # Get job ID for cancellation checks
    job_id = ENV['CURRENT_JOB_ID']
    
    # Track memory stats for performance metrics
    memory_stats = {
      start_time: Time.current,
      peaks: [],
      averages: [],
      batch_sizes: [],
      job_type: job_type || 'unknown'
    }
    
    # Check if job was cancelled before starting
    if job_id && job_cancelled?(job_id)
      Rails.logger.info "Job #{job_id} was cancelled before batch processing. Exiting."
      return []
    end
    
    # Process in batches to manage memory
    items.each_slice(batch_size) do |batch|
      begin
        # Check for cancellation before processing each batch
        if job_id && job_cancelled?(job_id)
          Rails.logger.info "Job #{job_id} was cancelled during batch processing. Stopping."
          break
        end
        
        batch_start_time = Time.current
        start_memory = memory_monitor.mb
        
        batch_updated_items = []
        
        # Process in smaller chunks to avoid large memory allocations
        batch.each_slice(processing_batch_size) do |processing_batch|
          # Check for cancellation during processing
          if job_id && job_cancelled?(job_id)
            Rails.logger.info "Job #{job_id} was cancelled during processing. Stopping."
            raise "Job cancelled" # This will be caught by the rescue below
          end
          
          # Process the batch with the API
          updated_batch = process_api_batch(processing_batch)
          batch_updated_items.concat(updated_batch)
          
          # Update in smaller chunks to avoid large DB transactions
          batch_updated_items.each_slice(50) do |update_chunk|
            update_content_batch(update_chunk)
            # Allow GC to collect the chunk after processing
            update_chunk = nil
            GC.start if memory_monitor.mb > memory_threshold * 0.8
          end
          updated_items.concat(batch_updated_items)
        end
        
        processed_items += batch.size
        
        # Collect metrics
        end_memory = memory_monitor.mb
        duration = Time.current - batch_start_time
        memory_stats[:peaks] << end_memory
        memory_stats[:averages] << (start_memory + end_memory) / 2
        memory_stats[:batch_sizes] << batch_size
        
        # Adaptive batch size adjustment
        if end_memory > memory_threshold * 0.9 # Getting close to threshold
          old_batch_size = batch_size
          batch_size = [(batch_size * 0.75).to_i, min_batch_size].max
          Rails.logger.warn "[Memory] High usage (#{end_memory.round(2)}MB). Reducing batch size from #{old_batch_size} to #{batch_size}"
        elsif end_memory < memory_threshold * 0.7 && duration < 30.seconds # Safe memory level and good performance
          old_batch_size = batch_size
          batch_size = [(batch_size * 1.2).to_i, ENV.fetch('MAX_BATCH_SIZE', 100).to_i].min
          Rails.logger.info "[Memory] Optimal usage (#{end_memory.round(2)}MB). Increasing batch size from #{old_batch_size} to #{batch_size}"
        end
        
        # Only yield for custom progress handling
        yield(processed_items, total_items) if block_given?
        
        # Clear variables to help GC
        batch_updated_items = nil
        batch = nil
        
        # Trigger GC only if memory usage is high
        if end_memory > memory_threshold * 0.8
          GC.start(full_mark: true, immediate_sweep: true)
          Rails.logger.info "[Memory] GC triggered at #{end_memory.round(2)}MB"
        end
        
        sleep(0.5)
      rescue => e
        if e.message == "Job cancelled"
          Rails.logger.info "Job was cancelled during processing. Exiting gracefully."
          break
        else
          Rails.logger.error("Error processing batch: #{e.message}")
          Rails.logger.error(e.backtrace.take(10).join("\n"))
          
          # On error, reduce batch sizes and continue with next batch
          batch_size = [batch_size / 2, min_batch_size].max
          processing_batch_size = [processing_batch_size / 2, min_processing_batch_size].max
          Rails.logger.warn "[Error Recovery] Reduced batch size to #{batch_size} and processing batch size to #{processing_batch_size}"
        end
      end
    end
    
    # Log performance metrics
    log_performance_metrics(memory_stats, processed_items)
    
    updated_items
  end
  
  # Helper method to check if a job is cancelled
  def self.job_cancelled?(job_id)
    return false unless job_id
    
    # Check if JobCancellationService exists and use it
    if defined?(JobCancellationService) && JobCancellationService.respond_to?(:cancelled?)
      JobCancellationService.cancelled?(job_id)
    else
      # Fallback to checking GoodJob directly if service doesn't exist
      GoodJob::Job.where(id: job_id).first&.cancelled?
    end
  rescue => e
    Rails.logger.error "Error checking job cancellation status: #{e.message}"
    false
  end

  def self.content_changed?(existing, new_attrs, type)
    # Common fields that should trigger an update for both types
    base_fields = %w[
      title description vote_average vote_count popularity status
      tagline imdb_id adult runtime plot_keywords
    ]

    # Type-specific fields
    type_fields = if type == 'movie'
      %w[runtime plot_keywords]
    else
      %w[tv_show_type number_of_seasons number_of_episodes in_production creators]
    end

    fields_to_check = base_fields + type_fields

    # Only check URL fields if they're nil in existing record
    url_fields = %w[poster_url backdrop_url trailer_url]
    url_fields.each do |field|
      fields_to_check << field if existing[field].nil?
    end

    # Check if any relevant field has changed
    fields_to_check.any? do |field|
      old_val = existing[field]
      new_val = new_attrs[field.to_sym]

      is_changed = case field
      when 'plot_keywords', 'directors', 'cast', 'creators'
        normalize_text(old_val) != normalize_text(new_val)
      when 'production_countries', 'spoken_languages'
        normalize_json(old_val) != normalize_json(new_val)
      else
        old_val != new_val
      end

      if is_changed
        puts "[#{type.upcase}][#{existing['title']}] Field #{field} changed from '#{old_val}' to '#{new_val}'"
      end
      is_changed
    end
  end

  private

  def self.normalize_text(text)
    return nil if text.nil?
    text.to_s.strip.downcase.split(',').map(&:strip).sort.join(',')
  end

  def self.normalize_json(json_string)
    return '[]' if json_string.blank?
    JSON.parse(json_string).sort_by { |item| item.to_s }
  rescue JSON::ParserError
    '[]'
  end

  def self.log_performance_metrics(stats, total_items)
    metrics = {
      peak_memory_mb: stats[:peaks].max.round(2),
      average_memory_mb: (stats[:averages].sum / stats[:averages].size).round(2),
      duration_seconds: (Time.current - stats[:start_time]).to_i,
      items_processed: total_items,
      batch_sizes: stats[:batch_sizes]
    }
    
    # Only create JobPerformanceMetric if we're in a job context
    if defined?(GoodJob::CurrentThread.active_job)
      JobPerformanceMetric.create!(
        good_job: GoodJob::CurrentThread.active_job,
        job_type: stats[:job_type],
        **metrics
      )
    end
    
    Rails.logger.info "[Performance] Process completed:" \
      "\n  Items: #{total_items}" \
      "\n  Peak Memory: #{metrics[:peak_memory_mb]}MB" \
      "\n  Average Memory: #{metrics[:average_memory_mb]}MB" \
      "\n  Duration: #{metrics[:duration_seconds]}s"
  end

  def self.update_content_details(id, type)
    # Your existing content update logic here
    # This should be the code that actually updates a single content item
    # from the TMDB API
  end

  # Process a batch of items with the API
  def self.process_api_batch(processing_batch)
    # Process each item in the batch
    processing_batch.map do |item|
      begin
        details = TmdbService.fetch_details(item['id'], item['type'] || (item['title'] ? 'movie' : 'tv'))
        details
      rescue => e
        Rails.logger.error("Error fetching details for item #{item['id']}: #{e.message}")
        nil
      end
    end.compact
  end
end
