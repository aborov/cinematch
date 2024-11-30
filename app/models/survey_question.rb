# frozen_string_literal: true

# == Schema Information
#
# Table name: survey_questions
#
#  id            :bigint           not null, primary key
#  question_text :string
#  question_type :string
#  survey_type   :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_survey_questions_on_survey_type  (survey_type)
#
class SurveyQuestion < ApplicationRecord
  has_many :survey_responses, foreign_key: 'survey_question_id'

  validates :question_text, presence: true, 
                           uniqueness: { scope: :survey_type, 
                                       message: "already exists for this survey type" }
  validates :question_type, presence: true
  validates :survey_type, presence: true

  scope :basic, -> { where(survey_type: 'basic') }
  scope :extended, -> { where(survey_type: 'extended') }

  # Helper methods for different question types
  scope :big_five, -> { where(question_type: ['openness', 'conscientiousness', 'extraversion', 'agreeableness', 'neuroticism']) }
  scope :hexaco, -> { where(question_type: 'honesty_humility') }
  scope :emotional_intelligence, -> { where(question_type: 'emotional_intelligence') }
  scope :attachment, -> { where(question_type: [
    'attachment',
    'attachment_secure',
    'attachment_anxious',
    'attachment_avoidant',
    'attachment_disorganized'
  ]) }
  scope :cognitive_style, -> { where(question_type: 'cognitive_style') }
  scope :moral_foundations, -> { where(question_type: 'moral_foundations') }
  scope :dark_triad, -> { where(question_type: 'dark_triad') }
  scope :narrative_transportation, -> { where(question_type: 'narrative_transportation') }

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "question_text", "question_type", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
