class ResetSurveyResponsesSequence < ActiveRecord::Migration[7.1]
  def up
    # Get the maximum ID from the survey_responses table
    max_id = execute("SELECT MAX(id) FROM survey_responses").first['max']
    
    if max_id
      # Reset the sequence to start from the next available ID
      execute("ALTER SEQUENCE survey_responses_id_seq RESTART WITH #{max_id + 1}")
    else
      # If table is empty, reset to 1
      execute("ALTER SEQUENCE survey_responses_id_seq RESTART WITH 1")
    end
  end

  def down
    # No need to do anything in down migration
  end
end
