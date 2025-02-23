class AddProcessingToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :processing, :boolean, default: false
  end
end
