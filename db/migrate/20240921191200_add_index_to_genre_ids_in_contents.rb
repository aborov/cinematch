class AddIndexToGenreIdsInContents < ActiveRecord::Migration[7.1]
  def change
    execute "CREATE INDEX index_contents_on_genre_ids ON contents USING gin (genre_ids gin_trgm_ops)"
  end

  def down
    remove_index :contents, :genre_ids
  end
end
