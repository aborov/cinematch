class AddRecommendedContentIdsToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :recommended_content_ids, :integer, array: true, default: []
  end
end
