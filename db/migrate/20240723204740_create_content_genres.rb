class CreateContentGenres < ActiveRecord::Migration[7.1]
  def change
    create_table :content_genres do |t|
      t.integer :content_id
      t.integer :genre_id

      t.timestamps
    end
  end
end
