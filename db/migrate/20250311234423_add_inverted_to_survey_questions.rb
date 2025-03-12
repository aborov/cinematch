class AddInvertedToSurveyQuestions < ActiveRecord::Migration[7.1]
  def change
    add_column :survey_questions, :inverted, :boolean, default: false
  end
end
