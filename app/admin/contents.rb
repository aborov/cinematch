ActiveAdmin.register Content do
  permit_params :title, :description, :poster_url, :trailer_url, :source_id, :source, 
                :release_year, :content_type, :plot_keywords, :adult, :runtime, :status

  index do
    selectable_column
    id_column
    column :title
    column :content_type
    column :release_year
    column :status
    column "Adult Content", :adult
    column :runtime do |content|
      content.runtime ? "#{content.runtime} min" : "N/A"
    end
    column :vote_average do |content|
      number_with_precision(content.vote_average, precision: 1)
    end
    column :updated_at
    actions
  end

  filter :title
  filter :content_type
  filter :release_year
  filter :adult
  filter :status
  filter :runtime
  filter :vote_average
  filter :created_at
  filter :updated_at

  show do
    attributes_table do
      row :id
      row :title
      row :description
      row :content_type
      row :release_year
      row :status
      row :runtime do |content|
        content.runtime ? "#{content.runtime} minutes" : "N/A"
      end
      row :adult
      row :vote_average do |content|
        number_with_precision(content.vote_average, precision: 1)
      end
      row :vote_count
      row :popularity
      row :genres do |content|
        Genre.where(tmdb_id: content.genre_ids_array).pluck(:name).join(", ")
      end
      row :production_countries do |content|
        content.production_countries_array.join(", ")
      end
      row :poster_url do |content|
        if content.poster_url.present?
          image_tag content.poster_url, style: "max-width: 200px"
        end
      end
      row :trailer_url do |content|
        if content.trailer_url.present?
          link_to "Watch Trailer", content.trailer_url, target: "_blank"
        end
      end
      row :source_id
      row :source
      row :plot_keywords
      row :created_at
      row :updated_at
    end

    panel "Raw Data" do
      attributes_table_for resource do
        row :genre_ids
        row :production_countries
        row :cast
        row :directors
      end
    end
  end

  form do |f|
    f.inputs do
      f.input :title
      f.input :description
      f.input :content_type, as: :select, collection: ['movie', 'tv']
      f.input :release_year
      f.input :status
      f.input :runtime
      f.input :adult
      f.input :poster_url
      f.input :trailer_url
      f.input :source_id
      f.input :source
      f.input :plot_keywords
    end
    f.actions
  end
end
