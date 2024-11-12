class DropContentGenresTable < ActiveRecord::Migration[7.1]
  def up
    drop_table :content_genres
  end

  def down
    create_table :content_genres do |t|
      t.references :content, foreign_key: true
      t.references :genre, foreign_key: true
      t.timestamps
    end
  end
end
