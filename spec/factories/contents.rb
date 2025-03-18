# == Schema Information
#
# Table name: contents
#
#  id                   :bigint           not null, primary key
#  adult                :boolean          default(FALSE)
#  backdrop_url         :string
#  cast                 :text
#  content_type         :string
#  creators             :text
#  description          :text
#  directors            :text
#  genre_ids            :text
#  in_production        :boolean
#  number_of_episodes   :integer
#  number_of_seasons    :integer
#  original_language    :string
#  plot_keywords        :text
#  popularity           :float
#  poster_url           :string
#  production_countries :text
#  release_year         :integer
#  runtime              :integer
#  source               :string
#  spoken_languages     :text
#  status               :string
#  tagline              :text
#  title                :string
#  tmdb_last_update     :datetime
#  trailer_url          :string
#  tv_show_type         :string
#  vote_average         :float
#  vote_count           :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  imdb_id              :string
#  source_id            :string
#
# Indexes
#
#  index_contents_on_genre_ids                   (genre_ids) USING gin
#  index_contents_on_imdb_id                     (imdb_id)
#  index_contents_on_source_id_and_content_type  (source_id,content_type) UNIQUE
#
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
