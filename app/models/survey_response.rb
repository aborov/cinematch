# frozen_string_literal: true

# == Schema Information
#
# Table name: survey_responses
#
#  id                 :integer          not null, primary key
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
end
