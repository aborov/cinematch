class UpdateWatchlistItemsForCompositeKey < ActiveRecord::Migration[6.1]
  def change
    add_column :watchlist_items, :source_id, :string
    add_column :watchlist_items, :content_type, :string
    add_index :watchlist_items, [:user_id, :source_id, :content_type], unique: true
    remove_column :watchlist_items, :content_id, :integer
  end
end
