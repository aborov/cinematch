class AddRecommendationsGeneratedAtToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :recommendations_generated_at, :datetime
  end
end
