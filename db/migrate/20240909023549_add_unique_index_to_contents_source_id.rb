class AddUniqueIndexToContentsSourceId < ActiveRecord::Migration[7.1]
  def change
    add_index :contents, :source_id, unique: true
  end
end
