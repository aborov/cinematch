class AddTmdbFieldsToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :vote_average, :float
    add_column :contents, :vote_count, :integer
    add_column :contents, :popularity, :float
    add_column :contents, :original_language, :string
    add_column :contents, :runtime, :integer
    add_column :contents, :status, :string
    add_column :contents, :tagline, :text
    add_column :contents, :backdrop_url, :string
    add_column :contents, :genre_ids, :text
  end
end
