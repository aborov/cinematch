class AddUniqueIndexToSurveyResponses < ActiveRecord::Migration[7.1]
  def up
    # First, remove duplicates keeping only the most recent response for each user-question pair
    execute <<-SQL
      DELETE FROM survey_responses
      WHERE id IN (
        SELECT id
        FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY user_id, survey_question_id
                   ORDER BY updated_at DESC
                 ) as rnum
          FROM survey_responses
          WHERE deleted_at IS NULL
        ) t
        WHERE t.rnum > 1
      );
    SQL

    # Then add the unique index
    add_index :survey_responses, [:user_id, :survey_question_id], 
              unique: true, 
              name: 'index_survey_responses_on_user_and_question',
              where: 'deleted_at IS NULL'
  end

  def down
    remove_index :survey_responses, name: 'index_survey_responses_on_user_and_question'
  end
end
