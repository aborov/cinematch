class AddPersonalitySummaryToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :personality_summary, :text
  end
end
