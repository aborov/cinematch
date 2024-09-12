# frozen_string_literal: true

# == Schema Information
#
# Table name: user_preferences
#
#  id                    :bigint           not null, primary key
#  deleted_at            :datetime
#  disable_adult_content :boolean
#  favorite_genres       :json
#  personality_profiles  :json
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_user_preferences_on_deleted_at  (deleted_at)
#  index_user_preferences_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserPreference < ApplicationRecord
  acts_as_paranoid
  belongs_to :user, required: true

  def personality_profiles
    read_attribute(:personality_profiles) || {}
  end

  def favorite_genres
    read_attribute(:favorite_genres) || []
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "favorite_genres", "id", "personality_profiles", "updated_at", "user_id"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
end
