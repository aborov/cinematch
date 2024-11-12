class AddDisableAdultContentToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :disable_adult_content, :boolean
  end
end
