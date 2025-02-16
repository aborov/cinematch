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

      TmdbTasks.process_content_in_batches(items) do |processed_items, total_items|
        progress = (processed_items.to_f / total_items * 100).round(2)
        puts "Progress: #{processed_items}/#{total_items} (#{progress}%)"
      end
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
      'popular' => 15,
      'top_rated' => 20,
      'now_playing' => 5,
      'upcoming' => 5
    }.flat_map do |category, pages|
      TmdbService.fetch_movies_by_category(category, pages)
    end
  end

  def fetch_tv_shows_by_categories
    {
      'popular' => 15,
      'top_rated' => 20,
      'on_the_air' => 5,
      'airing_today' => 5
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
      1950 => 5,
      1960 => 5,
      1970 => 8,
      1980 => 10,
      1990 => 12,
      2000 => 15,
      2010 => 20,
      2020 => 10
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
      'ja' => 15, # Japanese - more pages
      'ko' => 15, # Korean - more pages
      'hi' => 10, # Hindi
      'fr' => 8,  # French
      'es' => 8,  # Spanish
      'de' => 8,  # German
      'it' => 8,  # Italian
      'zh' => 8,  # Chinese
      'ru' => 8,  # Russian
      'pt' => 8,  # Portuguese
      'tr' => 5,  # Turkish
      'th' => 5   # Thai
    }
    
    languages.flat_map do |lang, pages|
      ['movie', 'tv'].flat_map do |type|
        TmdbService.fetch_by_language(lang, type, pages)
      end
    end
  end
end
