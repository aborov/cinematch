class UserPdf < Prawn::Document
  def initialize(users)
    super(page_size: "A4", page_layout: :landscape)
    @users = users
    generate_content
  end

  def generate_content
    text "Users Report", size: 18, style: :bold, align: :center
    move_down 20
    users_table
  end

  def users_table
    table user_rows do
      row(0).font_style = :bold
      self.header = true
      self.row_colors = ['DDDDDD', 'FFFFFF']
      self.cell_style = { size: 10, padding: [3, 3, 3, 3] }
      columns(0..6).align = :left
      self.width = 720
    end
  end

  def user_rows
    [['ID', 'Name', 'Email', 'Gender', 'Admin', 'Provider', 'Created At']] +
    @users.map do |user|
      [
        user.id,
        user.name,
        user.email,
        user.gender,
        user.admin? ? 'Yes' : 'No',
        user.provider,
        user.created_at&.strftime("%Y-%m-%d").to_s
      ]
    end
  end
end
