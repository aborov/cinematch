# frozen_string_literal: true

# == Schema Information
#
# Table name: contents
#
#  id            :integer          not null, primary key
#  content_type  :string
#  description   :text
#  plot_keywords :text
#  poster_url    :string
#  release_year  :integer
#  source        :string
#  title         :string
#  trailer_url   :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  source_id     :string
#
class Content < ApplicationRecord
  has_many :content_genres, class_name: 'ContentGenre', foreign_key: 'content_id', dependent: :destroy
  has_many :genres, through: :content_genres, source: :genre

  def self.ransackable_attributes(auth_object = nil)
    ["id", "title", "description", "poster_url", "trailer_url", "source_id", "source", "release_year", "content_type", "plot_keywords", "created_at", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
