class AddTmdbLastUpdateToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :tmdb_last_update, :datetime
  end
end
