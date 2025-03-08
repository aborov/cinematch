# frozen_string_literal: true

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
class Content < ApplicationRecord
  validates :title, presence: true
  validates :content_type, presence: true, inclusion: { in: %w[movie tv], message: "%{value} is not a valid content type" }
  validates :source_id, presence: true, uniqueness: { scope: :content_type }
  validates :imdb_id, uniqueness: true, allow_blank: true

  def self.ransackable_attributes(auth_object = nil)
    ["id", "title", "description", "poster_url", "trailer_url", "source_id", "source", "release_year", "content_type", "plot_keywords", "created_at", "updated_at", "vote_average", "vote_count", "popularity", "original_language", "runtime", "status", "tagline", "backdrop_url", "genre_ids", "production_countries", "directors", "cast", "tmdb_last_update", "adult"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  def parse_array_field(field)
    return [] if self[field].blank?
    
    case self[field]
    when String
      begin
        JSON.parse(self[field])
      rescue JSON::ParserError
        self[field].split(',').map(&:strip)
      end
    when Array
      self[field]
    when Integer, Float
      [self[field]]
    else
      Rails.logger.warn "[Content] Unexpected type for #{field}: #{self[field].class}"
      []
    end
  end

  def genre_ids_array
    parse_array_field(:genre_ids)
  end

  def genre_names
    Genre.where(tmdb_id: genre_ids_array).pluck(:name)
  end

  def production_countries_array
    JSON.parse(production_countries) if production_countries
  end

  def directors_array
    directors.split(',') if directors
  end

  def cast_array
    cast.split(',') if cast
  end

  def watchlist_items
    WatchlistItem.where(source_id: source_id, content_type: content_type)
  end

  def users_watchlisted
    User.joins(:watchlist_items).where(watchlist_items: { source_id: source_id, content_type: content_type })
  end

  def safe_array_display(field)
    value = self[field]
    return "[]" if value.blank?
    
    begin
      case value
      when String
        parsed = JSON.parse(value)
        parsed.is_a?(Array) ? parsed.inspect : "[]"
      when Array
        value.inspect
      else
        "[]"
      end
    rescue JSON::ParserError
      "[]"
    end
  end
end
