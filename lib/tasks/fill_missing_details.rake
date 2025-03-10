require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fill in missing details for existing content'
  task fill_missing_details: :environment do
    start_time = Time.now
    puts "Starting to fill missing details at #{start_time}"

    # Find items with missing details or that haven't been updated in a long time
    total_items = Content.where(tmdb_last_update: nil)
                         .or(Content.where('tmdb_last_update < ?', 2.weeks.ago))
                         .count
    
    puts "Total items to process: #{total_items}"
    
    # Exit early if no items need processing
    if total_items == 0
      puts "No items need details filled. Exiting."
      return
    end

    batch_size = (ENV['BATCH_SIZE'] || 100).to_i # Batch size for database queries
    processing_batch_size = 20 # Smaller batch size for API calls
    processed_count = 0
    updated_count = 0
    
    # Group items by content type for better logging
    content_types = Content.where(tmdb_last_update: nil)
                           .or(Content.where('tmdb_last_update < ?', 2.weeks.ago))
                           .group(:content_type)
                           .count
    
    puts "Items by type: #{content_types.map { |type, count| "#{type}: #{count}" }.join(', ')}"

    # Process each content type separately for better tracking
    content_types.each do |content_type, type_count|
      type_start_time = Time.now
      type_processed = 0
      type_updated = 0
      
      puts "Processing #{type_count} #{content_type} items..."
      
      loop do
        # Get the next batch of items that need updating for this type
        batch = Content.where(content_type: content_type)
                       .where(tmdb_last_update: nil)
                       .or(Content.where(content_type: content_type)
                       .where('tmdb_last_update < ?', 2.weeks.ago))
                       .limit(batch_size)
        
        break if batch.empty?

        items = batch.map do |content|
          {
            'id' => content.source_id,
            'type' => content.content_type,
            'title' => content.title,
            # Use title for both title and name to avoid nil errors
            'name' => content.title
          }
        end

        # Track which items were successfully updated
        updated_items = []
        
        # Process this batch
        # Pass a callback as a parameter instead of trying to chain blocks
        updated_items = TmdbTasks.process_content_in_batches(
          items, 
          batch_size: batch_size, 
          processing_batch_size: processing_batch_size,
          item_callback: lambda do |updated_item, existing_item|
            # This block is called for each successfully updated item
            if updated_item && existing_item
              item_name = updated_item['title'] || updated_item['name'] || "ID: #{updated_item['id']}"
              puts "[#{content_type.upcase}][#{item_name}] Details filled successfully"
              { source_id: updated_item['id'] }
            else
              nil
            end
          end
        ) do |inner_processed, inner_total|
          # Inner progress is handled by TmdbTasks
        end
        
        # Filter out nil values from the callback
        updated_items.compact!
        
        # Update tmdb_last_update for ALL processed items, not just updated ones
        # This prevents the same items from being selected in the next run
        if items.any?
          source_ids = items.map { |item| item['id'] }
          Content.where(source_id: source_ids, content_type: content_type)
                 .update_all(tmdb_last_update: Time.current)
          
          type_updated += updated_items.size
          updated_count += updated_items.size
        end

        type_processed += items.size
        processed_count += items.size
        
        # Calculate progress and ETA
        type_progress = (type_processed.to_f / type_count * 100).round(2)
        overall_progress = (processed_count.to_f / total_items * 100).round(2)
        
        # Calculate ETA
        eta = calculate_eta(type_start_time, type_processed, type_count)
        
        puts "[Fill Missing][#{content_type.upcase}] Progress: #{type_processed}/#{type_count} (#{type_progress}%) - Updated: #{type_updated} - ETA: #{eta}"
        puts "[Fill Missing][OVERALL] Progress: #{processed_count}/#{total_items} (#{overall_progress}%) - Updated: #{updated_count}"

        # Force garbage collection to free up memory
        GC.start

        break if type_processed >= type_count
      end
      
      type_duration = (Time.now - type_start_time).round(2)
      puts "Completed processing #{content_type} items in #{type_duration} seconds. Updated #{type_updated} items."
    end

    end_time = Time.now
    duration = (end_time - start_time).round(2)
    puts "Finished filling missing details at #{end_time}. Total duration: #{duration} seconds"
    puts "Total items processed: #{processed_count}, Total items updated: #{updated_count}"
    
    # Only trigger recommendations update if we had updates
    if updated_count > 0
      puts "Scheduling recommendation updates due to #{updated_count} items with filled details"
      UpdateAllRecommendationsJob.perform_later(batch_size: 50)
    else
      puts "No items updated, skipping recommendation updates"
    end
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

def fetch_trailer_url(videos)
  return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
  trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' } ||
            videos.find { |v| v['type'] == 'Teaser' && v['site'] == 'YouTube' }
  trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
end
