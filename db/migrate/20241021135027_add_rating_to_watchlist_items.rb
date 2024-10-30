class AddRatingToWatchlistItems < ActiveRecord::Migration[7.1]
  def change
    add_column :watchlist_items, :rating, :integer
  end
end
