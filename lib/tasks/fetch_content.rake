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
      { name: 'Content by decades', fetcher: -> { fetch_content_by_decades } }
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
    Genre.upsert_all(
      genres.map { |genre| { tmdb_id: genre['id'], name: genre['name'] } },
      unique_by: :tmdb_id
    )
    puts 'Genres have been fetched and stored successfully.'
    genres
  end

  def fetch_movies_by_categories
    %w[popular top_rated now_playing upcoming].flat_map do |category|
      TmdbService.fetch_movies_by_category(category)
    end
  end

  def fetch_tv_shows_by_categories
    %w[popular top_rated on_the_air airing_today].flat_map do |category|
      TmdbService.fetch_tv_shows_by_category(category)
    end
  end

  def fetch_content_by_genres(genres)
    genres.flat_map do |genre|
      TmdbService.fetch_by_genre(genre['id'], 'movie') +
      TmdbService.fetch_by_genre(genre['id'], 'tv')
    end
  end

  def fetch_content_by_decades
    (1950..2020).step(10).flat_map do |decade|
      TmdbService.fetch_by_decade(decade, decade + 9, 'movie') +
      TmdbService.fetch_by_decade(decade, decade + 9, 'tv')
    end
  end
end
