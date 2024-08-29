class SetDefaultAdminToFalse < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :admin, from: nil, to: false
  end
end
