namespace :tmdb do
  desc 'Update existing content from TMDb'
  task update_content: :environment do
    last_update = Content.maximum(:tmdb_last_update) || 1.week.ago
    
    updated_movie_ids = TmdbService.fetch_movie_changes(last_update)
    updated_tv_ids = TmdbService.fetch_tv_changes(last_update)
    
    updated_content = (updated_movie_ids + updated_tv_ids).map.with_index do |(id, type), index|
      puts "Fetching details for item #{index + 1} of #{updated_movie_ids.size + updated_tv_ids.size}..."
      TmdbService.fetch_details(id, type)
    end
    
    update_content_batch(updated_content)
    
    puts "Content has been updated successfully."
  end
end

def update_content_batch(content_list)
  content_attributes = content_list.map.with_index do |item, index|
    type = item['media_type'] || (item['title'] ? 'movie' : 'tv')
    details = TmdbService.fetch_details(item['id'], type)

    puts "Processing item #{index + 1} of #{content_list.size}: #{item['title'] || item['name']}"

    {
      source_id: item['id'].to_s,
      source: 'tmdb',
      title: item['title'] || item['name'],
      description: item['overview'],
      poster_url: item['poster_path'] ? "https://image.tmdb.org/t/p/w500#{item['poster_path']}" : nil,
      backdrop_url: item['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{item['backdrop_path']}" : nil,
      release_year: parse_release_year(item['release_date'] || item['first_air_date']),
      content_type: type,
      vote_average: item['vote_average'],
      vote_count: item['vote_count'],
      popularity: item['popularity'],
      original_language: item['original_language'],
      runtime: type == 'movie' ? details['runtime'] : details['episode_run_time']&.first,
      status: details['status'],
      tagline: details['tagline'],
      genre_ids: item['genre_ids'].is_a?(Array) ? item['genre_ids'].join(',') : item['genre_ids'],
      production_countries: details['production_countries'].to_json,
      directors: details['credits']&.dig('crew')&.select { |c| c['job'] == 'Director' }&.map { |d| d['name'] }&.join(',') || '',
      cast: details['credits']&.dig('cast')&.take(5)&.map { |c| c['name'] }&.join(',') || '',
      trailer_url: fetch_trailer_url(details['videos'] || []),
      adult: item['adult'] || details['adult'],
      tmdb_last_update: parse_tmdb_date(item['tmdb_last_update'] || details['last_updated'])
    }
  end

  Content.upsert_all(
    content_attributes,
    unique_by: :source_id,
    update_only: content_attributes.first.keys - [:source_id, :source]
  )
end

def fetch_trailer_url(videos)
  return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
  trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' }
  trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
end
