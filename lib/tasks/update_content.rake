require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Update existing content with significant changes from TMDb'
  task update_content: :environment do
    start_time = Time.now
    puts "Starting content update at #{start_time}"
    
    # Track statistics
    total_items_processed = 0
    items_with_significant_changes = 0
    items_with_minor_changes = 0
    
    begin
      # Get the last update time - default to 3 days ago if no recent updates
      last_update = Content.maximum(:tmdb_last_update) || 3.days.ago
      puts "Fetching changes since #{last_update}"

      # Limit the number of IDs to process for testing
      updated_movie_ids = TmdbService.fetch_movie_changes(last_update)
      updated_tv_ids = TmdbService.fetch_tv_changes(last_update)

      total_updates = updated_movie_ids.size + updated_tv_ids.size
      puts "Found #{updated_movie_ids.size} movie updates and #{updated_tv_ids.size} TV show updates"

      # Process movies
      if updated_movie_ids.any?
        significant_changes, minor_changes = process_significant_updates(updated_movie_ids, 'movie') do |processed, total, significant, minor|
          progress = (processed.to_f / total * 100).round(2)
          eta = calculate_eta(start_time, processed, total)
          puts "[Update Content] Movies: #{processed}/#{total} (#{progress}%) - Significant changes: #{significant}, Minor changes: #{minor} - ETA: #{eta}"
        end
        items_with_significant_changes += significant_changes
        items_with_minor_changes += minor_changes
      end
      
      # Process TV shows
      if updated_tv_ids.any?
        significant_changes, minor_changes = process_significant_updates(updated_tv_ids, 'tv') do |processed, total, significant, minor|
          progress = (processed.to_f / total * 100).round(2)
          eta = calculate_eta(start_time, processed, total)
          puts "[Update Content] TV Shows: #{processed}/#{total} (#{progress}%) - Significant changes: #{significant}, Minor changes: #{minor} - ETA: #{eta}"
        end
        items_with_significant_changes += significant_changes
        items_with_minor_changes += minor_changes
      end

      puts "Content update completed. Total items processed: #{total_updates}"
      puts "Items with significant changes: #{items_with_significant_changes}"
      puts "Items with minor changes skipped: #{items_with_minor_changes}"
      
      # Only trigger recommendations update if we had significant changes
      if items_with_significant_changes > 0
        puts "Scheduling recommendation updates due to #{items_with_significant_changes} items with significant changes"
        UpdateAllRecommendationsJob.perform_later(batch_size: 50)
      else
        puts "No significant changes, skipping recommendation updates"
      end
    rescue => e
      puts "Error during content update: #{e.message}"
      puts e.backtrace.join("\n")
    ensure
      end_time = Time.now
      puts "Content update task ended at #{end_time}. Total duration: #{(end_time - start_time).round(2)} seconds"
    end
  end
  
  # Process updates but only apply significant changes
  def process_significant_updates(item_ids, content_type)
    batch_size = 50
    total_items = item_ids.size
    processed_count = 0
    significant_changes_count = 0
    minor_changes_count = 0
    
    # Define what fields are considered significant
    significant_fields = [
      'title', 'name', 'overview', 'genres', 'release_date', 'first_air_date',
      'status', 'runtime', 'episode_count', 'season_count', 'content_type',
      'poster_path', 'backdrop_path', 'trailer_url', 'imdb_id'
    ]
    
    # Define thresholds for numerical fields
    numerical_thresholds = {
      'popularity' => 20.0,     # Only update if popularity changed by 20 or more
      'vote_average' => 0.5,    # Only update if rating changed by 0.5 or more
      'vote_count' => 1000      # Only update if vote count changed by 1000 or more
    }
    
    item_ids.each_slice(batch_size) do |batch_ids|
      items = batch_ids.map { |id| { 'id' => id, 'type' => content_type } }
      
      # Get current database records for these items - convert to strings for comparison
      existing_items = Content.where(source_id: batch_ids.map(&:to_s), content_type: content_type).index_by(&:source_id)
      
      # Process the batch with custom handling for changes
      updated_items = []
      
      # Pass a callback as a parameter instead of trying to chain blocks
      TmdbTasks.process_content_in_batches(
        items, 
        batch_size: batch_size, 
        processing_batch_size: 10,
        item_callback: lambda do |item, existing_content|
          # Skip if we couldn't find the item in our database
          next nil unless existing_content
          
          # Check for significant changes
          has_significant_changes = false
          
          # Check text/object fields
          significant_fields.each do |field|
            next unless item[field].present? && existing_content[field] != item[field]
            
            # If any significant field changed, mark for update
            puts "[#{content_type.upcase}][#{item['title'] || item['name']}] Significant change in field #{field}"
            has_significant_changes = true
            break
          end
          
          # Check numerical fields against thresholds
          unless has_significant_changes
            numerical_thresholds.each do |field, threshold|
              next unless item[field].present? && existing_content[field].present?
              
              current_value = existing_content[field].to_f
              new_value = item[field].to_f
              difference = (new_value - current_value).abs
              
              if difference >= threshold
                puts "[#{content_type.upcase}][#{item['title'] || item['name']}] Significant numerical change in #{field}: #{current_value} -> #{new_value} (diff: #{difference.round(3)})"
                has_significant_changes = true
                break
              else
                puts "[#{content_type.upcase}][#{item['title'] || item['name']}] Minor change in #{field}: #{current_value} -> #{new_value} (diff: #{difference.round(3)}) - skipping"
              end
            end
          end
          
          if has_significant_changes
            significant_changes_count += 1
            updated_items << item
            true # Process this item
          else
            minor_changes_count += 1
            false # Skip updating this item
          end
        end
      ) do |inner_processed, inner_total|
        # Inner progress tracking is handled by TmdbTasks
      end
      
      processed_count += batch_ids.size
      
      # Report progress
      yield(processed_count, total_items, significant_changes_count, minor_changes_count) if block_given?
      
      # Force garbage collection after each batch
      GC.start
    end
    
    [significant_changes_count, minor_changes_count]
  end
  
  def calculate_eta(start_time, processed, total)
    return "calculating..." if processed == 0
    
    elapsed = Time.now - start_time
    items_per_second = processed.to_f / elapsed
    remaining_items = total - processed
    
    return "complete" if remaining_items <= 0
    
    seconds_remaining = (remaining_items / items_per_second).round
    
    if seconds_remaining < 60
      "#{seconds_remaining}s"
    elsif seconds_remaining < 3600
      "#{(seconds_remaining / 60).round}m #{seconds_remaining % 60}s"
    else
      "#{(seconds_remaining / 3600).round}h #{(seconds_remaining % 3600 / 60).round}m"
    end
  end
end
