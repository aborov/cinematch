# == Schema Information
#
# Table name: survey_questions
#
#  id            :integer          not null, primary key
#  question_text :string
#  question_type :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class SurveyQuestion < ApplicationRecord
  has_many :survey_responses, foreign_key: "survey_question_id"
end
