# frozen_string_literal: true

# == Schema Information
#
# Table name: genres
#
#  id         :integer          not null, primary key
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

  scope :by_tmdb_id, ->(tmdb_id) { where(tmdb_id: tmdb_id) }

  def self.find_by_tmdb_ids(tmdb_ids)
    where(tmdb_id: tmdb_ids)
  end
end
