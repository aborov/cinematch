FactoryBot.define do
  factory :content do
    sequence(:title) { |n| "Test Content #{n}" }
    sequence(:source_id) { |n| "tt#{n.to_s.rjust(7, '0')}" }
    content_type { "movie" }
    release_year { 2023 }
    vote_average { 7.5 }
    genre_ids { [28, 12] } # Action, Adventure by default
    adult { false }
    
    trait :movie do
      content_type { "movie" }
    end
    
    trait :tv do
      content_type { "tv" }
    end
    
    trait :adult do
      adult { true }
    end
    
    trait :action do
      genre_ids { [28] } # Action
    end
    
    trait :adventure do
      genre_ids { [12] } # Adventure
    end
    
    trait :comedy do
      genre_ids { [35] } # Comedy
    end
    
    trait :drama do
      genre_ids { [18] } # Drama
    end
    
    trait :with_poster do
      poster_url { "https://image.tmdb.org/t/p/w500/poster.jpg" }
    end
    
    trait :with_backdrop do
      backdrop_url { "https://image.tmdb.org/t/p/original/backdrop.jpg" }
    end
    
    trait :with_production_countries do
      production_countries { [{"iso_3166_1" => "US", "name" => "United States of America"}] }
    end
  end
end 
