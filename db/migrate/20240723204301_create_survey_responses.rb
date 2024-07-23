class CreateSurveyResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :survey_responses do |t|
      t.integer :survey_question_id
      t.string :response
      t.integer :user_id

      t.timestamps
    end
  end
end
