class CreateWatchlistItems < ActiveRecord::Migration[7.1]
  def change
    create_table :watchlist_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :content, null: false, foreign_key: true
      t.boolean :watched, default: false
      t.integer :position

      t.timestamps
    end

    add_index :watchlist_items, [:user_id, :content_id], unique: true
  end
end
