class AddUseAiToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :use_ai, :boolean, default: false
  end
end
