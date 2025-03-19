class CreateUserRecommendations < ActiveRecord::Migration[7.1]
  def change
    create_table :user_recommendations do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :recommended_content_ids, array: true, default: []
      t.datetime :recommendations_generated_at
      t.jsonb :recommendation_reasons
      t.jsonb :recommendation_scores
      t.boolean :processing, default: false
      t.datetime :deleted_at
      
      t.timestamps
    end
    
    add_index :user_recommendations, :deleted_at
    
    # Add survey completion tracking columns to user_preferences
    add_column :user_preferences, :basic_survey_completed, :boolean, default: false
    add_column :user_preferences, :extended_survey_completed, :boolean, default: false
    add_column :user_preferences, :extended_survey_in_progress, :boolean, default: false

    # Data migration
    reversible do |dir|
      dir.up do
        # Create a user recommendation for each user preference
        execute <<-SQL
          INSERT INTO user_recommendations (
            user_id, 
            recommended_content_ids, 
            recommendations_generated_at, 
            recommendation_reasons, 
            recommendation_scores, 
            processing, 
            created_at, 
            updated_at
          )
          SELECT 
            user_id, 
            recommended_content_ids, 
            recommendations_generated_at, 
            recommendation_reasons, 
            recommendation_scores, 
            processing, 
            created_at, 
            updated_at
          FROM user_preferences
          WHERE user_preferences.deleted_at IS NULL;
        SQL
        
        # Update the survey completion status in user_preferences based on survey responses
        # This is not efficient but works for a one-time migration
        User.find_each do |user|
          # Using the existing model methods to calculate survey completion
          user_preference = user.user_preference
          next unless user_preference
          
          user_preference.update_columns(
            basic_survey_completed: user.basic_survey_completed?,
            extended_survey_completed: user.extended_survey_completed?,
            extended_survey_in_progress: user.extended_survey_in_progress?
          )
        end
      end
    end
    
    # Remove columns from user_preferences that are now in user_recommendations
    remove_column :user_preferences, :recommended_content_ids, :integer, array: true, default: []
    remove_column :user_preferences, :recommendations_generated_at, :datetime
    remove_column :user_preferences, :recommendation_reasons, :jsonb
    remove_column :user_preferences, :recommendation_scores, :jsonb
    remove_column :user_preferences, :processing, :boolean, default: false
  end
end
