class CreateSurveyQuestions < ActiveRecord::Migration[7.1]
  def change
    create_table :survey_questions do |t|
      t.string :question_text
      t.string :question_type

      t.timestamps
    end
  end
end
