# == Schema Information
#
# Table name: user_preferences
#
#  id                   :integer          not null, primary key
#  favorite_genres      :json
#  personality_profiles :json
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  user_id              :integer          not null
#
# Indexes
#
#  index_user_preferences_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class UserPreference < ApplicationRecord
  belongs_to :user, required: true, class_name: "User", foreign_key: "user_id"
end
