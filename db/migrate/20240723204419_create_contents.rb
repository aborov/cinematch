class CreateContents < ActiveRecord::Migration[7.1]
  def change
    create_table :contents do |t|
      t.string :title
      t.text :description
      t.string :poster_url
      t.string :trailer_url
      t.string :source_id
      t.string :source
      t.integer :release_year
      t.string :content_type
      t.text :plot_keywords

      t.timestamps
    end
  end
end
