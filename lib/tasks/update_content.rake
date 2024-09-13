require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Update existing content from TMDb'
  task update_content: :environment do
    last_update = Content.maximum(:tmdb_last_update) || 1.week.ago
    puts "Fetching changes since #{last_update}"

    updated_movie_ids = TmdbService.fetch_movie_changes(last_update)
    updated_tv_ids = TmdbService.fetch_tv_changes(last_update)

    total_updates = updated_movie_ids.size + updated_tv_ids.size
    puts "Found #{updated_movie_ids.size} movie updates and #{updated_tv_ids.size} TV show updates"

    updated_content = []
    processed_items = 0

    (updated_movie_ids + updated_tv_ids).each_slice(20).with_index do |batch, batch_index|
      batch.each_with_index do |(id, type), index|
        puts "Fetching details for item #{processed_items + index + 1} of #{total_updates}..."
        updated_content << TmdbService.fetch_details(id, type)
      end

      TmdbTasks.update_content_batch(updated_content)
      processed_items += batch.size
      progress = (processed_items.to_f / total_updates * 100).round(2)
      puts "Progress: #{processed_items}/#{total_updates} (#{progress}%)"
      updated_content.clear
    end

    puts "Content update completed. Total items processed: #{total_updates}"
  end
end
