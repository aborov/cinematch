FactoryBot.define do
  factory :survey_response do
    association :user
    association :survey_question
    response { Faker::Lorem.word }
  end
end 
