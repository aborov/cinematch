class RemoveSingleSourceIdConstraint < ActiveRecord::Migration[7.1]
  def change
    remove_index :contents, :source_id
  end
end
