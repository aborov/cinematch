class AddDeletedAtToSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :survey_responses, :deleted_at, :datetime
    add_index :survey_responses, :deleted_at
  end
end
