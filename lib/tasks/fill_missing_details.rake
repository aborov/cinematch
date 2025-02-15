require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fill in missing details for existing content'
  task fill_missing_details: :environment do
    start_time = Time.now
    puts "Starting to fill missing details at #{start_time}"

    total_items = Content.where(tmdb_last_update: nil).or(Content.where('tmdb_last_update < ?', 1.week.ago)).count
    puts "Total items to process: #{total_items}"

    batch_size = 100 # Reduced from 1000 to prevent memory spikes
    processed_count = 0
    updated_count = 0

    loop do
      # Get the next batch of items that need updating
      batch = Content.where(tmdb_last_update: nil).or(Content.where('tmdb_last_update < ?', 1.week.ago)).limit(batch_size)
      
      break if batch.empty?

      items = batch.map do |content|
        {
          'id' => content.source_id,
          'type' => content.content_type
        }
      end

      updated_items = TmdbTasks.process_content_in_batches(items, batch_size: 100, processing_batch_size: 20)
      
      # Update tmdb_last_update for processed items
      Content.where(source_id: updated_items.map { |item| item[:source_id] })
             .update_all(tmdb_last_update: Time.current)

      processed_count += items.size
      updated_count += updated_items.size
      progress = (processed_count.to_f / total_items * 100).round(2)
      puts "Progress: #{processed_count}/#{total_items} (#{progress}%). Updated: #{updated_count}"

      # Force garbage collection to free up memory
      GC.start

      break if processed_count >= total_items
    end

    end_time = Time.now
    duration = (end_time - start_time).round(2)
    puts "Finished filling missing details at #{end_time}. Total duration: #{duration} seconds"
    puts "Total items processed: #{processed_count}, Total items updated: #{updated_count}"
  end
end

def fetch_trailer_url(videos)
  return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
  trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' } ||
            videos.find { |v| v['type'] == 'Teaser' && v['site'] == 'YouTube' }
  trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
end
