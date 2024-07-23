# == Schema Information
#
# Table name: genres
#
#  id         :integer          not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Genre < ApplicationRecord
  has_many :content_genres, class_name: "ContentGenre", foreign_key: "genre_id", dependent: :destroy
  has_many :contents, through: :content_genres, source: :content
end
