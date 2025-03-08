module TmdbTasks
  def self.update_content_batch(content_list)
    puts "Processing #{content_list.size} items"
    
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
    
    content_attributes = content_list.map do |item|
      type = item['type'] || (item['title'] ? 'movie' : 'tv')
      details = TmdbService.fetch_details(item['id'], type)

      next if details['title'].blank? && details['name'].blank?

      # Start with a hash containing all keys set to nil
      attributes = all_keys.each_with_object({}) { |key, hash| hash[key] = nil }
      
      # Then fill in the values we have
      attributes.merge!(
        source_id: item['id'].to_s,
        source: 'tmdb',
        title: details['title'] || details['name'],
        description: details['overview'],
        poster_url: details['poster_path'] ? "https://image.tmdb.org/t/p/w500#{details['poster_path']}" : nil,
        backdrop_url: details['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{details['backdrop_path']}" : nil,
        release_year: parse_release_year(details['release_date'] || details['first_air_date']),
        content_type: type == 'movie' ? 'movie' : 'tv',
        vote_average: details['vote_average'],
        vote_count: details['vote_count'],
        popularity: details['popularity'],
        original_language: details['original_language'],
        status: details['status'],
        tagline: details['tagline'],
        genre_ids: details['genres']&.map { |g| g['id'] }&.join(',') || '',
        production_countries: details['production_countries']&.to_json || '[]',
        directors: details['credits']&.dig('crew')&.select { |c| c['job'] == 'Director' }&.map { |d| d['name'] }&.join(',') || '',
        cast: details['credits']&.dig('cast')&.take(5)&.map { |c| c['name'] }&.join(',') || '',
        trailer_url: fetch_trailer_url(details['videos']&.dig('results') || []),
        imdb_id: details['external_ids']&.dig('imdb_id') || details['imdb_id'],
        adult: details['adult'],
        spoken_languages: details['spoken_languages']&.to_json || '[]',
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
        attributes[:runtime] = details['runtime']
        attributes[:plot_keywords] = details['keywords']&.dig('keywords')&.map { |k| k['name'] }&.join(',') || ''
      else # TV show
        attributes[:runtime] = details['episode_run_time']&.first
        attributes[:plot_keywords] = details['keywords']&.dig('results')&.map { |k| k['name'] }&.join(',') || ''
        attributes[:tv_show_type] = details['type']
        attributes[:number_of_seasons] = details['number_of_seasons']
        attributes[:number_of_episodes] = details['number_of_episodes']
        attributes[:in_production] = details['in_production']
        attributes[:creators] = details['created_by']&.map { |c| c['name'] }&.join(',') || ''
      end

      # Check for changes using the pre-fetched content with both source_id and content_type
      existing_content = existing_contents[[item['id'].to_s, type]]
      if existing_content
        changed = content_changed?(existing_content, attributes, type)
        attributes[:tmdb_last_update] = Time.current if changed
      else
        attributes[:tmdb_last_update] = Time.current
      end

      attributes
    end.compact

    puts "Found #{content_attributes.size} valid items"

    # Remove duplicates based on source_id and content_type
    unique_content_attributes = content_attributes.uniq { |item| [item[:source_id], item[:content_type]] }

    if unique_content_attributes.any?
      Content.upsert_all(
        unique_content_attributes,
        unique_by: [:source_id, :content_type],  # Updated to use composite unique key
        update_only: unique_content_attributes.first.keys - [:source_id, :source, :content_type]
      )
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

  def self.process_content_in_batches(items, batch_size: 20, processing_batch_size: 5, skip_existing: false, item_callback: nil)
    total_items = items.size
    processed_items = 0
    processed_results = []
    
    # First, filter out items we already have that were recently updated
    if skip_existing
      existing_content = Content.where(source_id: items.map { |i| i['id'] })
      recently_updated_ids = existing_content.pluck(:source_id)
      
      items_to_process = items.reject { |item| recently_updated_ids.include?(item['id']) }
      puts "Processing #{items_to_process.size} out of #{total_items} items (#{recently_updated_ids.size} skipped)"
    else
      items_to_process = items
    end
    
    items_to_process.each_slice(batch_size) do |batch|
      begin
        GC.start # Force garbage collection before processing new batch
        
        updated_content = batch.each_slice(processing_batch_size).flat_map do |processing_batch|
          processing_batch.map do |item|
            begin
              type = item['type'] || (item['title'] ? 'movie' : 'tv')
              details = TmdbService.fetch_details(item['id'], type)
              
              # If we have an item callback, use it to determine if we should process this item
              if item_callback
                # Find existing content for this item
                existing = Content.find_by(source_id: item['id'], content_type: type)
                
                # Call the callback with the item and existing content
                result = item_callback.call(details, existing)
                
                # If the callback returns false, skip this item
                if result == false
                  nil
                else
                  # If the callback returns something other than false, add it to results
                  processed_results << result if result != true
                  details
                end
              else
                details
              end
            rescue => e
              Rails.logger.error("Error fetching details for item #{item['id']}: #{e.message}")
              nil
            end
          end
        end.compact
        
        update_content_batch(updated_content) if updated_content.any?
        processed_items += batch.size
        
        # Only yield for custom progress handling
        yield(processed_items, total_items) if block_given?
        
        sleep(0.5)
      rescue => e
        Rails.logger.error("Error processing batch: #{e.message}")
      end
    end
    
    # Return processed results if we have a callback, otherwise nil
    item_callback ? processed_results : nil
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
end
