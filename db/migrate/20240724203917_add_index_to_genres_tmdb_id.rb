class AddIndexToGenresTmdbId < ActiveRecord::Migration[7.1]
  def change
    add_index :genres, :tmdb_id, unique: true
  end
end
