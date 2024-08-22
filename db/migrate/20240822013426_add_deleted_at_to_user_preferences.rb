class AddDeletedAtToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :deleted_at, :datetime
    add_index :user_preferences, :deleted_at
  end
end
