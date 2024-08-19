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
end
