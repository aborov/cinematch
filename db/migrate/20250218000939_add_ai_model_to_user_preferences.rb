class AddAiModelToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :ai_model, :string
  end
end
