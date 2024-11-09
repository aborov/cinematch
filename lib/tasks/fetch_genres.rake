# frozen_string_literal: true
require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fetch and store genres from TMDb'
  task fetch_genres: :environment do
    puts "Starting to fetch genres..."
    genres = TmdbService.fetch_genres[:all_genres]
    puts "Fetched #{genres.size} genres from TMDb"

    ActiveRecord::Base.transaction do
      genres.each do |genre|
        Genre.find_or_create_by!(tmdb_id: genre['id']) do |g|
          g.name = genre['name']
          puts "Creating genre: #{g.name} (#{g.tmdb_id})"
        end
      end
    end

    puts "Genres in database after update: #{Genre.count}"
    puts 'Genres have been fetched and stored successfully.'
  end
end
