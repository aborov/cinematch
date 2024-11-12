class AddTvShowTypeToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :tv_show_type, :string
  end
end
