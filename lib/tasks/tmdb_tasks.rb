module TmdbTasks
  def self.update_content_batch(content_list)
    puts "Processing #{content_list.size} items"
    content_attributes = content_list.map do |item|
      type = item['type'] || (item['title'] ? 'movie' : 'tv')
      details = TmdbService.fetch_details(item['id'], type)

      next if details['title'].blank? && details['name'].blank?

      attributes = {
        source_id: item['id'].to_s,
        source: 'tmdb',
        title: details['title'] || details['name'],
        description: details['overview'],
        poster_url: details['poster_path'] ? "https://image.tmdb.org/t/p/w500#{details['poster_path']}" : nil,
        backdrop_url: details['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{details['backdrop_path']}" : nil,
        release_year: parse_release_year(details['release_date'] || details['first_air_date']),
        content_type: type == 'movie' ? 'movie' : 'tv',  # This ensures content_type is always 'movie' or 'tv'
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
        tmdb_last_update: parse_tmdb_date(item['tmdb_last_update'] || details['last_updated'])
      }

      if type == 'movie'
        attributes[:runtime] = details['runtime']
        attributes[:plot_keywords] = details['keywords']&.dig('keywords')&.map { |k| k['name'] }&.join(',') || ''
        # Clear any TV-specific attributes
        attributes[:tv_show_type] = nil
        attributes[:number_of_seasons] = nil
        attributes[:number_of_episodes] = nil
        attributes[:in_production] = nil
        attributes[:creators] = nil
      else # TV show
        attributes[:runtime] = details['episode_run_time']&.first
        attributes[:plot_keywords] = details['keywords']&.dig('results')&.map { |k| k['name'] }&.join(',') || ''
        attributes[:tv_show_type] = details['type']  # Store the specific TV show type here
        attributes[:number_of_seasons] = details['number_of_seasons']
        attributes[:number_of_episodes] = details['number_of_episodes']
        attributes[:in_production] = details['in_production']
        attributes[:creators] = details['created_by']&.map { |c| c['name'] }&.join(',') || ''
      end

      attributes
    end.compact

    puts "Found #{content_attributes.size} valid items"

    # Remove duplicates based on source_id
    unique_content_attributes = content_attributes.uniq { |item| item[:source_id] }

    if unique_content_attributes.any?
      Content.upsert_all(
        unique_content_attributes,
        unique_by: :source_id,
        update_only: unique_content_attributes.first.keys - [:source_id, :source]
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

  def self.process_content_in_batches(items, batch_size: 20, processing_batch_size: 5)
    total_items = items.size
    processed_items = 0
    
    items.each_slice(batch_size) do |batch|
      begin
        GC.start # Force garbage collection before processing new batch
        
        updated_content = batch.each_slice(processing_batch_size).flat_map do |processing_batch|
          processing_batch.map do |item|
            Rails.logger.info "Processing item #{item['id']}"
            TmdbService.fetch_details(item['id'], item['type'] || (item['title'] ? 'movie' : 'tv'))
          rescue => e
            Rails.logger.error("Error fetching details for item #{item['id']}: #{e.message}")
            nil
          end
        end.compact
        
        update_content_batch(updated_content)
        processed_items += batch.size
        yield(processed_items, total_items) if block_given?
        
        # Sleep briefly between batches to prevent memory buildup
        sleep(0.5)
      rescue => e
        Rails.logger.error("Error processing batch: #{e.message}")
      end
    end
  end
end
