FactoryBot.define do
  factory :survey_question do
    question_text { Faker::Lorem.question }
    question_type { ['multiple_choice', 'text', 'rating'].sample }
    survey_type { ['personality', 'preferences'].sample }
    position { rand(1..10) }
    correct_answer { nil }
  end
end 
