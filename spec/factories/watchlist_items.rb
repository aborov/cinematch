FactoryBot.define do
  factory :watchlist_item do
    association :user
    association :content
    watched { false }
    rating { nil }
    
    trait :watched do
      watched { true }
    end
    
    trait :rated do
      watched { true }
      rating { 8 }
    end
    
    trait :highly_rated do
      watched { true }
      rating { 10 }
    end
    
    trait :low_rated do
      watched { true }
      rating { 3 }
    end
  end
end 
