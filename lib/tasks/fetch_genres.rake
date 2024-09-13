# frozen_string_literal: true
require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fetch and store genres from TMDb'
  task fetch_genres: :environment do
    genres = TmdbService.fetch_genres[:all_genres]

    genres.each do |genre|
      Genre.find_or_create_by!(tmdb_id: genre['id']) do |g|
        g.name = genre['name']
      end
    end

    puts 'Genres have been fetched and stored successfully.'
  end
end
