module UserActivityTracking
  extend ActiveSupport::Concern

  included do
    before_action :track_user_activity
  end

  private

  def track_user_activity
    # Skip for ActiveAdmin controllers
    return if self.class.name.start_with?('Admin::') || self.class.name.start_with?('ActiveAdmin::')
    
    return unless current_user
    return if current_user.last_active_at&.> 5.minutes.ago

    current_user.touch_last_active
  end
end
