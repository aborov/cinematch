class AddMissingFieldsToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :production_countries, :text
    add_column :contents, :directors, :text
    add_column :contents, :cast, :text
  end
end
