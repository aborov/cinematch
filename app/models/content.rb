# frozen_string_literal: true

# == Schema Information
#
# Table name: contents
#
#  id                   :integer          not null, primary key
#  backdrop_url         :string
#  cast                 :text
#  content_type         :string
#  description          :text
#  directors            :text
#  genre_ids            :text
#  original_language    :string
#  plot_keywords        :text
#  popularity           :float
#  poster_url           :string
#  production_countries :text
#  release_year         :integer
#  runtime              :integer
#  source               :string
#  status               :string
#  tagline              :text
#  title                :string
#  trailer_url          :string
#  vote_average         :float
#  vote_count           :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  source_id            :string
#
class Content < ApplicationRecord
  def self.ransackable_attributes(auth_object = nil)
    ["id", "title", "description", "poster_url", "trailer_url", "source_id", "source", "release_year", "content_type", "plot_keywords", "created_at", "updated_at", "vote_average", "vote_count", "popularity", "original_language", "runtime", "status", "tagline", "backdrop_url", "genre_ids", "production_countries", "directors", "cast"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  def genre_ids_array
    genre_ids.split(',').map(&:to_i) if genre_ids.present?
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

  private

  def update_genre_associations
    return unless genre_ids_changed?

    self.genres = Genre.where(tmdb_id: genre_ids_array)
  end
end
