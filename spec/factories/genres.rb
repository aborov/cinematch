# == Schema Information
#
# Table name: genres
#
#  id         :bigint           not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  tmdb_id    :integer
#
# Indexes
#
#  index_genres_on_tmdb_id  (tmdb_id) UNIQUE
#
FactoryBot.define do
  factory :genre do
    sequence(:name) { |n| "Genre #{n}" }
    sequence(:tmdb_id) { |n| n }
    
    trait :action do
      name { "Action" }
      tmdb_id { 28 }
    end
    
    trait :adventure do
      name { "Adventure" }
      tmdb_id { 12 }
    end
    
    trait :comedy do
      name { "Comedy" }
      tmdb_id { 35 }
    end
    
    trait :drama do
      name { "Drama" }
      tmdb_id { 18 }
    end
    
    trait :horror do
      name { "Horror" }
      tmdb_id { 27 }
    end
    
    trait :romance do
      name { "Romance" }
      tmdb_id { 10749 }
    end
    
    trait :science_fiction do
      name { "Science Fiction" }
      tmdb_id { 878 }
    end
    
    trait :thriller do
      name { "Thriller" }
      tmdb_id { 53 }
    end
  end
end 
