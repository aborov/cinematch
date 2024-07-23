# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

User.create!(name: "John Doe", email: "john@example.com", password: "password", gender: "Male", dob: "1990-01-01")
SurveyQuestion.create!([
  { question_text: "I enjoy trying new things.", question_type: "openness" },
  { question_text: "I am always prepared.", question_type: "conscientiousness" },
  { question_text: "I am the life of the party.", question_type: "extraversion" },
  { question_text: "I sympathize with others' feelings.", question_type: "agreeableness" },
  { question_text: "I get stressed out easily.", question_type: "neuroticism" },
  # Add more questions as needed
])
