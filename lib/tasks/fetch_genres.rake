# frozen_string_literal: true

namespace :tmdb do
  desc 'Fetch and store genres from TMDb'
  task fetch_genres: :environment do
    genres = TmdbService.fetch_genres

    genres.each do |genre|
      existing_genre = Genre.find_by(tmdb_id: genre['id'])
      if existing_genre
        existing_genre.update(name: genre['name'])
      else
        Genre.create(tmdb_id: genre['id'], name: genre['name'])
      end
    end

    puts 'Genres have been fetched and stored successfully.'
  end
end
