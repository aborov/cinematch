namespace :tmdb do
  desc 'Fetch and store genres and content from TMDb'
  task fetch_content: :environment do
    # Fetch and store genres first
    genres = TmdbService.fetch_genres[:all_genres]
    genres.each do |genre|
      Genre.find_or_create_by!(tmdb_id: genre['id']) do |g|
        g.name = genre['name']
      end
    end
    puts 'Genres have been fetched and stored successfully.'

    # Now fetch and store content
    movies = TmdbService.fetch_popular_movies + TmdbService.fetch_top_rated_movies + TmdbService.fetch_upcoming_movies
    tv_shows = TmdbService.fetch_popular_tv_shows + TmdbService.fetch_top_rated_tv_shows
    content = (movies + tv_shows).uniq { |item| item['id'] }

    content.each do |item|
      type = item['media_type'] || (item['title'] ? 'movie' : 'tv')
      details = TmdbService.fetch_details(item['id'], type)
      
      content = Content.find_or_initialize_by(source_id: item['id'].to_s, source: 'tmdb')
      content.assign_attributes(
        title: item['title'] || item['name'],
        description: item['overview'],
        poster_url: item['poster_path'] ? "https://image.tmdb.org/t/p/w500#{item['poster_path']}" : nil,
        backdrop_url: item['backdrop_path'] ? "https://image.tmdb.org/t/p/w1280#{item['backdrop_path']}" : nil,
        release_year: (item['release_date'] || item['first_air_date'])&.split('-')&.first&.to_i,
        content_type: type,
        vote_average: item['vote_average'],
        vote_count: item['vote_count'],
        popularity: item['popularity'],
        original_language: item['original_language'],
        runtime: type == 'movie' ? details['runtime'] : details['episode_run_time']&.first,
        status: details['status'],
        tagline: details['tagline'],
        genre_ids: item['genre_ids'].join(','),
        production_countries: details['production_countries'].to_json,
        directors: details['credits']['crew'].select { |c| c['job'] == 'Director' }.map { |d| d['name'] }.join(','),
        cast: details['credits']['cast'].take(5).map { |c| c['name'] }.join(','),
        trailer_url: fetch_trailer_url(details['videos']['results'])
      )
      content.save!
    end

    puts 'Content has been fetched and stored successfully.'
  end

  def fetch_trailer_url(videos)
    trailer = videos.find { |v| v['type'] == 'Trailer' && v['site'] == 'YouTube' }
    trailer ? "https://www.youtube.com/watch?v=#{trailer['key']}" : nil
  end
end
