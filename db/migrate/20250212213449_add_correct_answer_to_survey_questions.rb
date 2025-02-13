class AddCorrectAnswerToSurveyQuestions < ActiveRecord::Migration[7.1]
  def change
    add_column :survey_questions, :correct_answer, :string
    add_column :survey_questions, :position, :integer
  end
end
