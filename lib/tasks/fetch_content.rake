require_relative 'tmdb_tasks'
require 'parallel'

namespace :tmdb do
  desc 'Fetch new content and update existing content from TMDb'
  task fetch_content: :environment do
    start_time = Time.now
    puts "Starting to fetch content at #{start_time}"

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
    puts "Starting to fetch content from #{total_fetchers} sources..."

    fetchers.each_with_index do |fetcher_info, index|
      puts "Fetching from source #{index + 1} of #{total_fetchers}: #{fetcher_info[:name]}..."
      items = fetcher_info[:fetcher].call
      puts "Found #{items.size} items from #{fetcher_info[:name]}"

      # Split items by type and process separately
      movies = items.select { |item| item['type'] == 'movie' || item['title'].present? }
      tv_shows = items.select { |item| item['type'] == 'tv' || (!item['title'].present? && item['name'].present?) }

      puts "Processing #{movies.size} movies..."
      TmdbTasks.process_content_in_batches(movies) do |processed_items, total_items|
        progress = (processed_items.to_f / total_items * 100).round(2)
        puts "[Fetch Content][#{fetcher_info[:name]}] Movies: #{processed_items}/#{total_items} (#{progress}%)"
      end if movies.any?

      puts "Processing #{tv_shows.size} TV shows..."
      TmdbTasks.process_content_in_batches(tv_shows) do |processed_items, total_items|
        progress = (processed_items.to_f / total_items * 100).round(2)
        puts "[Fetch Content][#{fetcher_info[:name]}] TV Shows: #{processed_items}/#{total_items} (#{progress}%)"
      end if tv_shows.any?
    end

    end_time = Time.now
    puts "All content has been fetched and processed at #{end_time}. Total duration: #{(end_time - start_time).round(2)} seconds"
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
      TmdbService.fetch_tv_shows_by_category(category, pages)
    end
  end

  def fetch_content_by_genres(genres)
    genres.flat_map do |genre|
      TmdbService.fetch_by_genre(genre['id'], 'movie') +
      TmdbService.fetch_by_genre(genre['id'], 'tv')
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
      ['movie', 'tv'].flat_map do |type|
        TmdbService.fetch_by_decade(decade, decade + 9, type, pages)
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
      ['movie', 'tv'].flat_map do |type|
        TmdbService.fetch_by_keyword(keyword, type, 10)
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
      ['movie', 'tv'].flat_map do |type|
        TmdbService.fetch_by_language(lang, type, pages)
      end
    end
  end
end
