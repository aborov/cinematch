require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fill in missing details for existing content'
  task fill_missing_details: :environment do
    batch_size = 100
    total_count = Content.count
    processed_count = 0
    updated_count = 0

    puts "Starting to fill missing details for #{total_count} items..."

    Content.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |content|
        begin
          details = TmdbService.fetch_details(content.source_id, content.content_type)
          
          updates = {
            title: details['title'] || details['name'],
            description: details['overview'],
            poster_url: details['poster_path'] ? "https://image.tmdb.org/t/p/w500#{details['poster_path']}" : nil,
            backdrop_url: details['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{details['backdrop_path']}" : nil,
            release_year: TmdbTasks.parse_release_year(details['release_date'] || details['first_air_date']),
            vote_average: details['vote_average'],
            vote_count: details['vote_count'],
            popularity: details['popularity'],
            original_language: details['original_language'],
            runtime: content.content_type == 'movie' ? details['runtime'] : details['episode_run_time']&.first,
            status: details['status'],
            tagline: details['tagline'],
            genre_ids: details['genres']&.map { |g| g['id'] }&.join(',') || '',
            production_countries: details['production_countries']&.to_json || '[]',
            directors: details['credits']&.dig('crew')&.select { |c| c['job'] == 'Director' }&.map { |d| d['name'] }&.join(',') || '',
            cast: details['credits']&.dig('cast')&.take(5)&.map { |c| c['name'] }&.join(',') || '',
            trailer_url: fetch_trailer_url(details['videos']&.dig('results') || []),
            imdb_id: details['external_ids']&.dig('imdb_id') || details['imdb_id'],
            plot_keywords: content.content_type == 'movie' ? 
              details['keywords']&.dig('keywords')&.map { |k| k['name'] }&.join(',') || '' :
              details['keywords']&.dig('results')&.map { |k| k['name'] }&.join(',') || '',
            adult: details['adult'],
            spoken_languages: details['spoken_languages']&.to_json || '[]',
            number_of_seasons: content.content_type == 'tv' ? details['number_of_seasons'] : nil,
            number_of_episodes: content.content_type == 'tv' ? details['number_of_episodes'] : nil,
            in_production: content.content_type == 'tv' ? details['in_production'] : nil,
            creators: content.content_type == 'tv' ? 
              details['created_by']&.map { |c| c['name'] }&.join(',') || '' : nil
          }

          if content.update(updates)
            updated_count += 1
          end
        rescue => e
          puts "Error updating content ID: #{content.id}, Type: #{content.content_type}. Error: #{e.message}"
          puts "Details: #{details.inspect}"
          puts e.backtrace.join("\n")
        end

        processed_count += 1
        if processed_count % 100 == 0
          progress = (processed_count.to_f / total_count * 100).round(2)
          puts "Progress: #{processed_count}/#{total_count} (#{progress}%). Updated: #{updated_count}"
        end
      end
    end

    puts "Finished filling missing details. Total items processed: #{total_count}, Updated: #{updated_count}"
  end
end

def fetch_trailer_url(videos)
  return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
  trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' } ||
            videos.find { |v| v['type'] == 'Teaser' && v['site'] == 'YouTube' }
  trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
end
