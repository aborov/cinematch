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

  # Big Five Personality Traits
  scope :big_five, -> { where("question_type LIKE 'big5_%'") }
  scope :openness, -> { where("question_type LIKE 'big5_openness_%'") }
  scope :conscientiousness, -> { where("question_type LIKE 'big5_conscientiousness_%'") }
  scope :extraversion, -> { where("question_type LIKE 'big5_extraversion_%'") }
  scope :agreeableness, -> { where("question_type LIKE 'big5_agreeableness_%'") }
  scope :neuroticism, -> { where("question_type LIKE 'big5_neuroticism_%'") }

  # HEXACO Personality Traits
  scope :hexaco, -> { where("question_type LIKE 'hexaco_%'") }

  # Emotional Intelligence
  scope :emotional_intelligence_basic, -> { where("question_type LIKE 'ei_%' AND survey_type = 'basic'") }
  scope :emotional_intelligence_extended, -> { where("question_type LIKE 'ei_%' AND survey_type = 'extended'") }

  # Attachment Style
  scope :attachment, -> { where("question_type LIKE 'attachment_%'") }

  # Cognitive Style
  scope :cognitive, -> { where("question_type LIKE 'cognitive_%'") }

  # Moral Foundations and Values
  scope :moral, -> { where("question_type LIKE 'moral_%'") }

  # Dark Triad/Tetrad
  scope :dark_triad, -> { where("question_type LIKE 'dark_%'") }

  # Narrative Preferences
  scope :narrative, -> { where("question_type LIKE 'narrative_%'") }

  # Psychological Needs
  scope :psychological, -> { where("question_type LIKE 'psych_%'") }

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "id", "question_text", "question_type", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
