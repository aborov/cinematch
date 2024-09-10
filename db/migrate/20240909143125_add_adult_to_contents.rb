class AddAdultToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :adult, :boolean, default: false
  end
end
