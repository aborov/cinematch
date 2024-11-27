class AddWarningSentAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :warning_sent_at, :datetime
    add_index :users, :warning_sent_at
  end
end
