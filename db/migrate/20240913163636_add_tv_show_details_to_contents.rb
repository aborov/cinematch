class AddTvShowDetailsToContents < ActiveRecord::Migration[7.1]
  def change
    add_column :contents, :number_of_seasons, :integer
    add_column :contents, :number_of_episodes, :integer
    add_column :contents, :in_production, :boolean
    add_column :contents, :creators, :text
    add_column :contents, :spoken_languages, :text
  end
end
