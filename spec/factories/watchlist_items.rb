# == Schema Information
#
# Table name: watchlist_items
#
#  id           :bigint           not null, primary key
#  content_type :string
#  position     :integer
#  rating       :integer
#  watched      :boolean          default(FALSE)
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  source_id    :string
#  user_id      :bigint           not null
#
# Indexes
#
#  index_watchlist_items_on_user_id                                 (user_id)
#  index_watchlist_items_on_user_id_and_source_id_and_content_type  (user_id,source_id,content_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
