class AddRecommendationScoresToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :recommendation_scores, :jsonb, default: {}
  end
end
