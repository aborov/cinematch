# frozen_string_literal: true

# == Schema Information
#
# Table name: survey_questions
#
#  id             :bigint           not null, primary key
#  correct_answer :string
#  position       :integer
#  question_text  :string
#  question_type  :string
#  survey_type    :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_survey_questions_on_survey_type  (survey_type)
#
class SurveyQuestion < ApplicationRecord
  has_many :survey_responses, foreign_key: 'survey_question_id'

  validates :question_text, uniqueness: { scope: :question_type }, presence: true
  validates :question_type, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "question_text", "question_type", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
