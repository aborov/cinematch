# frozen_string_literal: true

# == Schema Information
#
# Table name: survey_responses
#
#  id                 :integer          not null, primary key
#  response           :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  survey_question_id :integer
#  user_id            :integer
#
class SurveyResponse < ApplicationRecord
  belongs_to :user, required: true
  belongs_to :survey_question, required: true
end
