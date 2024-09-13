class AddImdbIdToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :imdb_id, :string
    add_index :contents, :imdb_id
  end
end
