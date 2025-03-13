# == Schema Information
#
# Table name: survey_questions
#
#  id             :bigint           not null, primary key
#  correct_answer :string
#  inverted       :boolean          default(FALSE)
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
FactoryBot.define do
  factory :survey_question do
    question_text { Faker::Lorem.question }
    question_type { ['multiple_choice', 'text', 'rating'].sample }
    survey_type { ['personality', 'preferences'].sample }
    position { rand(1..10) }
    correct_answer { nil }
  end
end 
