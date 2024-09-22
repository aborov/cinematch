# == Schema Information
#
# Table name: watchlist_items
#
#  id         :bigint           not null, primary key
#  position   :integer
#  watched    :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  content_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_watchlist_items_on_content_id              (content_id)
#  index_watchlist_items_on_user_id                 (user_id)
#  index_watchlist_items_on_user_id_and_content_id  (user_id,content_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (content_id => contents.id)
#  fk_rails_...  (user_id => users.id)
#
class WatchlistItem < ApplicationRecord
  belongs_to :user
  belongs_to :content

  validates :user_id, uniqueness: { scope: :content_id }

  acts_as_list scope: [:user_id, watched: false]

  scope :unwatched, -> { where(watched: false).order(:position) }
  scope :watched, -> { where(watched: true).order(updated_at: :desc) }
end
