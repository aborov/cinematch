require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Update existing content from TMDb'
  task update_content: :environment do
    start_time = Time.now
    puts "Starting content update at #{start_time}"
    begin
      last_update = Content.maximum(:tmdb_last_update) || 1.week.ago
      puts "Fetching changes since #{last_update}"

      updated_movie_ids = TmdbService.fetch_movie_changes(last_update)
      updated_tv_ids = TmdbService.fetch_tv_changes(last_update)

      total_updates = updated_movie_ids.size + updated_tv_ids.size
      puts "Found #{updated_movie_ids.size} movie updates and #{updated_tv_ids.size} TV show updates"

      items = updated_movie_ids.map { |id| { 'id' => id, 'type' => 'movie' } } +
              updated_tv_ids.map { |id| { 'id' => id, 'type' => 'tv' } }

      TmdbTasks.process_content_in_batches(items) do |processed_items, total_items|
        progress = (processed_items.to_f / total_items * 100).round(2)
        puts "Progress: #{processed_items}/#{total_items} (#{progress}%)"
      end

      puts "Content update completed. Total items processed: #{total_updates}"
    rescue => e
      puts "Error during content update: #{e.message}"
    ensure
      end_time = Time.now
      puts "Content update task ended at #{end_time}. Total duration: #{(end_time - start_time).round(2)} seconds"
    end
  end
end
