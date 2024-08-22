class AddIndexToUsersDeletedAt < ActiveRecord::Migration[7.1]
  def change
    add_index :users, :deleted_at
  end
end
