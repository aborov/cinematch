namespace :tmdb do
  desc 'Fetch new content and update existing content from TMDb'
  task fetch_content: :environment do
    require 'parallel'

    # Fetch and store genres first
    genres = TmdbService.fetch_genres[:all_genres]
    Genre.upsert_all(
      genres.map { |genre| { tmdb_id: genre['id'], name: genre['name'] } },
      unique_by: :tmdb_id
    )
    puts 'Genres have been fetched and stored successfully.'

    # Define the fetchers
    fetchers = [
      -> { fetch_movies_by_categories },
      -> { fetch_tv_shows_by_categories },
      -> { fetch_content_by_genres(genres) },
      -> { fetch_content_by_decades }
    ]

    total_fetchers = fetchers.size
    puts "Starting to fetch content from #{total_fetchers} sources..."

    # Fetch new content and update existing content
    content_list = Parallel.map(fetchers.each_with_index) do |fetcher, index|
      puts "Fetching from source #{index + 1} of #{total_fetchers}..."
      fetcher.call
    end.flatten

    puts "Fetched #{content_list.size} items."

    content_list.uniq! { |item| item['id'] }

    update_content_batch(content_list)

    puts 'Content has been fetched, stored, and updated successfully.'
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

  def update_content_batch(content_list)
    content_attributes = content_list.map do |item|
      type = item['media_type'] || (item['title'] ? 'movie' : 'tv')
      details = TmdbService.fetch_details(item['id'], type)

      {
        source_id: item['id'].to_s,
        source: 'tmdb',
        title: item['title'] || item['name'],
        description: item['overview'],
        poster_url: item['poster_path'] ? "https://image.tmdb.org/t/p/w500#{item['poster_path']}" : nil,
        backdrop_url: item['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{item['backdrop_path']}" : nil,
        release_year: parse_release_year(item['release_date'] || item['first_air_date']),
        content_type: type,
        vote_average: item['vote_average'],
        vote_count: item['vote_count'],
        popularity: item['popularity'],
        original_language: item['original_language'],
        runtime: type == 'movie' ? details['runtime'] : details['episode_run_time']&.first,
        status: details['status'],
        tagline: details['tagline'],
        genre_ids: item['genre_ids'].is_a?(Array) ? item['genre_ids'].join(',') : item['genre_ids'],
        production_countries: details['production_countries'].to_json,
        directors: details['credits']['crew'].select { |c| c['job'] == 'Director' }.map { |d| d['name'] }.join(','),
        cast: details['credits']['cast'].take(5).map { |c| c['name'] }.join(','),
        trailer_url: fetch_trailer_url(details['videos']['results']),
        adult: item['adult'] || details['adult'],
        tmdb_last_update: parse_tmdb_date(item['tmdb_last_update'] || details['last_updated'])
      }
    end

    Content.upsert_all(
      content_attributes,
      unique_by: :source_id,
      update_only: content_attributes.first.keys - [:source_id, :source]
    )
  end

  def parse_tmdb_date(date_string)
    date_string.present? ? Time.parse(date_string) : nil
  rescue ArgumentError
    nil
  end

  def parse_release_year(date_string)
    date_string.present? ? date_string.split('-').first.to_i : nil
  end

  def fetch_trailer_url(videos)
    return nil if videos.nil? || !videos.is_a?(Array) || videos.empty?
    trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' }
    trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
  end
end
