class UserPreferencePdf < Prawn::Document
  def initialize(user_preferences)
    super()
    @user_preferences = user_preferences
    generate_content
  end

  private

  def generate_content
    text "User Preferences Report", size: 18, style: :bold, align: :center
    move_down 20
    user_preferences_table
  end

  def user_preferences_table
    table user_preference_rows do
      row(0).font_style = :bold
      self.header = true
      self.row_colors = ['DDDDDD', 'FFFFFF']
      self.column_widths = [40, 100, 200, 200]
    end
  end

  def user_preference_rows
    [['ID', 'User', 'Favorite Genres', 'Personality Profiles']] +
    @user_preferences.map do |preference|
      [preference.id, preference.user.name, preference.favorite_genres.join(", "), preference.personality_profiles.to_s]
    end
  end
end
