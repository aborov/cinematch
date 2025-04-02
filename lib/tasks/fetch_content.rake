require_relative 'tmdb_tasks'
require 'parallel'

namespace :tmdb do
  desc 'Fetch new content from TMDb (only adds new items, does not update existing)'
  task fetch_content: :environment do
    start_time = Time.now
    puts "Starting to fetch new content at #{start_time}"
    
    # Track statistics
    total_items_processed = 0
    new_items_added = 0
    skipped_existing = 0

    genres = fetch_and_store_genres

    fetchers = [
      { name: 'Movies by categories', fetcher: -> { fetch_movies_by_categories } },
      { name: 'TV shows by categories', fetcher: -> { fetch_tv_shows_by_categories } },
      { name: 'Content by genres', fetcher: -> { fetch_content_by_genres(genres) } },
      { name: 'Content by decades', fetcher: -> { fetch_content_by_decades } },
      { name: 'Content by keywords', fetcher: -> { fetch_content_by_keywords } },
      { name: 'Content by language', fetcher: -> { fetch_content_by_language } }
    ]

    total_fetchers = fetchers.size
    puts "Starting to fetch new content from #{total_fetchers} sources..."

    fetchers.each_with_index do |fetcher_info, index|
      fetcher_start_time = Time.now
      puts "Fetching from source #{index + 1} of #{total_fetchers}: #{fetcher_info[:name]}..."
      items = fetcher_info[:fetcher].call
      puts "Found #{items.size} items from #{fetcher_info[:name]}"

      # Split items by type and process separately
      movies = items.select { |item| item['type'] == 'movie' || item['title'].present? }
      tv_shows = items.select { |item| item['type'] == 'tv' || (!item['title'].present? && item['name'].present?) }

      # Process movies - only add new ones
      if movies.any?
        puts "Processing #{movies.size} movies from #{fetcher_info[:name]}..."
        new_added, skipped = process_new_content_only(movies, 'movie') do |processed, total, new_added, skipped|
          progress = (processed.to_f / total * 100).round(2)
          eta = calculate_eta(fetcher_start_time, processed, total)
          puts "[Fetch New Content][#{fetcher_info[:name]}] Movies: #{processed}/#{total} (#{progress}%) - Added: #{new_added}, Skipped: #{skipped} - ETA: #{eta}"
        end
        new_items_added += new_added
        skipped_existing += skipped
      end

      # Process TV shows - only add new ones
      if tv_shows.any?
        puts "Processing #{tv_shows.size} TV shows from #{fetcher_info[:name]}..."
        new_added, skipped = process_new_content_only(tv_shows, 'tv') do |processed, total, new_added, skipped|
          progress = (processed.to_f / total * 100).round(2)
          eta = calculate_eta(fetcher_start_time, processed, total)
          puts "[Fetch New Content][#{fetcher_info[:name]}] TV Shows: #{processed}/#{total} (#{progress}%) - Added: #{new_added}, Skipped: #{skipped} - ETA: #{eta}"
        end
        new_items_added += new_added
        skipped_existing += skipped
      end
      
      # Force garbage collection after each fetcher to manage memory
      GC.start
      
      fetcher_end_time = Time.now
      duration = (fetcher_end_time - fetcher_start_time).round(2)
      puts "Completed fetching from #{fetcher_info[:name]} in #{duration} seconds"
    end

    end_time = Time.now
    total_duration = (end_time - start_time).round(2)
    puts "New content fetching completed at #{end_time}."
    puts "Total duration: #{total_duration} seconds"
    puts "Total new items added: #{new_items_added}, Skipped existing: #{skipped_existing}"
    
    # If new items were added, trigger recommendations update
    if new_items_added > 0
      puts "Scheduling recommendation updates due to #{new_items_added} new items added"
      UpdateAllRecommendationsJob.perform_later(batch_size: 50)
    else
      puts "No new items added, skipping recommendation updates"
    end
  end

  # Process content items but only add new ones, skip existing
  def process_new_content_only(items, content_type)
    batch_size = 100
    total_items = items.size
    processed_count = 0
    new_items_count = 0
    skipped_count = 0
    
    items.each_slice(batch_size) do |batch|
      # Extract source IDs from the batch
      source_ids = batch.map { |item| item['id'].to_s }
      
      # Find which items already exist in the database
      existing_ids = Content.where(source_id: source_ids, content_type: content_type).pluck(:source_id)
      existing_ids_set = Set.new(existing_ids.map(&:to_s))
      
      # Filter to only new items
      new_items = batch.reject { |item| existing_ids_set.include?(item['id'].to_s) }
      
      # Process only the new items
      if new_items.any?
        TmdbTasks.process_content_in_batches(new_items, skip_existing: true) do |_processed, _total|
          # This inner progress is handled by TmdbTasks
        end
        new_items_count += new_items.size
      end
      
      # Update counters
      skipped_count += (batch.size - new_items.size)
      processed_count += batch.size
      
      # Report progress
      yield(processed_count, total_items, new_items_count, skipped_count) if block_given?
    end
    
    [new_items_count, skipped_count]
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

  def fetch_and_store_genres
    genres = TmdbService.fetch_genres[:all_genres]
    puts "Fetched #{genres.size} genres from TMDb"
    
    ActiveRecord::Base.transaction do
      result = Genre.upsert_all(
        genres.map { |genre| { tmdb_id: genre['id'], name: genre['name'] } },
        unique_by: :tmdb_id
      )
      puts "Inserted/Updated #{result.length} genres in the database"
    end
    
    puts 'Genres have been fetched and stored successfully.'
    genres
  end

  def fetch_movies_by_categories
    {
      'popular' => 30,      # 600 items
      'top_rated' => 30,    # 600 items
      'now_playing' => 15,  # 300 items
      'upcoming' => 15      # 300 items
    }.flat_map do |category, pages|
      puts "Fetching movies from category: #{category} (#{pages} pages)"
      TmdbService.fetch_movies_by_category(category, pages)
    end
  end

  def fetch_tv_shows_by_categories
    {
      'popular' => 30,        # 600 items
      'top_rated' => 30,      # 600 items
      'on_the_air' => 15,     # 300 items
      'airing_today' => 15    # 300 items
    }.flat_map do |category, pages|
      puts "Fetching TV shows from category: #{category} (#{pages} pages)"
      TmdbService.fetch_tv_shows_by_category(category, pages)
    end
  end

  def fetch_content_by_genres(genres)
    genres.flat_map do |genre|
      puts "Fetching content for genre: #{genre['name']} (ID: #{genre['id']})"
      movies = TmdbService.fetch_by_genre(genre['id'], 'movie')
      tv = TmdbService.fetch_by_genre(genre['id'], 'tv')
      puts "Found #{movies.size} movies and #{tv.size} TV shows for genre: #{genre['name']}"
      movies + tv
    end
  end

  def fetch_content_by_decades
    decades = {
      1950 => 10,
      1960 => 10,
      1970 => 15,
      1980 => 20,
      1990 => 25,
      2000 => 30,
      2010 => 35,
      2020 => 20
    }
    
    decades.flat_map do |decade, pages|
      decade_end = decade + 9
      puts "Fetching content from decade: #{decade}-#{decade_end}"
      ['movie', 'tv'].flat_map do |type|
        content = TmdbService.fetch_by_decade(decade, decade_end, type, pages)
        puts "Found #{content.size} #{type} items from decade #{decade}-#{decade_end}"
        content
      end
    end
  end

  def fetch_content_by_keywords
    popular_keywords = [
      'cyberpunk', 'post-apocalyptic', 'dystopia', 'time-travel',
      'supernatural', 'psychological', 'film-noir', 'steampunk',
      'martial-arts', 'biography', 'historical', 'musical'
    ]
    
    popular_keywords.flat_map do |keyword|
      puts "Fetching content with keyword: #{keyword}"
      ['movie', 'tv'].flat_map do |type|
        content = TmdbService.fetch_by_keyword(keyword, type, 10)
        puts "Found #{content.size} #{type} items with keyword: #{keyword}"
        content
      end
    end
  end

  def fetch_content_by_language
    languages = {
      'ja' => 25,  # Japanese
      'ko' => 25,  # Korean
      'hi' => 20,  # Hindi
      'fr' => 15,  # French
      'es' => 15,  # Spanish
      'de' => 15,  # German
      'it' => 15,  # Italian
      'zh' => 15,  # Chinese
      'ru' => 15,  # Russian
      'pt' => 15,  # Portuguese
      'tr' => 10,  # Turkish
      'th' => 10   # Thai
    }
    
    languages.flat_map do |lang, pages|
      language_name = {
        'ja' => 'Japanese', 'ko' => 'Korean', 'hi' => 'Hindi',
        'fr' => 'French', 'es' => 'Spanish', 'de' => 'German',
        'it' => 'Italian', 'zh' => 'Chinese', 'ru' => 'Russian',
        'pt' => 'Portuguese', 'tr' => 'Turkish', 'th' => 'Thai'
      }[lang] || lang
      
      puts "Fetching content in language: #{language_name} (#{lang})"
      ['movie', 'tv'].flat_map do |type|
        content = TmdbService.fetch_by_language(lang, type, pages)
        puts "Found #{content.size} #{type} items in language: #{language_name}"
        content
      end
    end
  end
end
