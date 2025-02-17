class AddRecommendationReasonsToUserPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :user_preferences, :recommendation_reasons, :jsonb, default: {}
  end
end
