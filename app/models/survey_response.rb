# frozen_string_literal: true

# == Schema Information
#
# Table name: survey_responses
#
#  id                 :bigint           not null, primary key
#  deleted_at         :datetime
#  response           :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  survey_question_id :integer
#  user_id            :integer
#
# Indexes
#
#  index_survey_responses_on_deleted_at  (deleted_at)
#
class SurveyResponse < ApplicationRecord
  acts_as_paranoid
  belongs_to :user, required: true
  belongs_to :survey_question, required: true

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "response", "survey_question_id", "updated_at", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["survey_question", "user"]
  end
end
