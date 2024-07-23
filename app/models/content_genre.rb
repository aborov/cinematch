# == Schema Information
#
# Table name: content_genres
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  content_id :integer
#  genre_id   :integer
#
class ContentGenre < ApplicationRecord
  belongs_to :content, required: true, class_name: "Content", foreign_key: "content_id"
  belongs_to :genre, required: true, class_name: "Genre", foreign_key: "genre_id"
end
