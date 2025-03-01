class CreateFetcherStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :fetcher_statuses do |t|
      t.string :provider, null: false
      t.datetime :last_run
      t.string :status, default: 'idle'
      t.integer :movies_fetched, default: 0
      
      t.timestamps
    end
    
    add_index :fetcher_statuses, :provider, unique: true
  end
end 
