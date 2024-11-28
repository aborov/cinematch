class AddSurveyTypeToSurveyQuestions < ActiveRecord::Migration[7.0]
  def change
    add_column :survey_questions, :survey_type, :string
    add_index :survey_questions, :survey_type
  end
end
