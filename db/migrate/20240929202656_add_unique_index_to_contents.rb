class AddUniqueIndexToContents < ActiveRecord::Migration[7.1]
  def change
    add_index :contents, [:source_id, :content_type], unique: true
  end
end
