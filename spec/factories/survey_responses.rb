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
FactoryBot.define do
  factory :survey_response do
    association :user
    association :survey_question
    response { Faker::Lorem.word }
  end
end 
