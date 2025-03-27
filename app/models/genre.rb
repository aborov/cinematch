# frozen_string_literal: true

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
class Genre < ApplicationRecord
  COMBINED_GENRES = ['Sci-Fi & Fantasy', 'Action & Adventure', 'War & Politics'].freeze

  scope :by_tmdb_id, ->(tmdb_id) { where(tmdb_id: tmdb_id) }

  def self.find_by_tmdb_ids(tmdb_ids)
    where(tmdb_id: tmdb_ids)
  end

  def self.user_facing_genres
    where.not(name: COMBINED_GENRES).map do |genre|
      { 'id' => genre.tmdb_id, 'name' => genre.name }
    end
  end
end
