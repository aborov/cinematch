ActiveAdmin.register Content do
  permit_params :title, :description, :poster_url, :trailer_url, :source_id, :source, :release_year, :content_type, :plot_keywords

  index do
    selectable_column
    id_column
    column :title
    column :content_type
    column :release_year
    column :source
    actions
  end

  filter :title
  filter :content_type
  filter :release_year
  filter :source

  form do |f|
    f.inputs do
      f.input :title
      f.input :description
      f.input :poster_url
      f.input :trailer_url
      f.input :source_id
      f.input :source
      f.input :release_year
      f.input :content_type, as: :select, collection: ['movie', 'tv']
      f.input :plot_keywords
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :title
      row :description
      row :poster_url
      row :trailer_url
      row :source_id
      row :source
      row :release_year
      row :content_type
      row :plot_keywords
      row :created_at
      row :updated_at
    end
  end
end
