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
class WatchlistItem < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: { scope: [:source_id, :content_type] }
  validates :rating, inclusion: { in: 1..10 }, allow_nil: true
  
  acts_as_list scope: [:user_id, watched: false]

  scope :unwatched, -> { where(watched: false).order(:position) }
  scope :watched, -> { where(watched: true).order(updated_at: :desc) }

  def content
    Content.find_by(source_id: source_id, content_type: content_type)
  end
end
