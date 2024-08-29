ActiveAdmin.register SurveyResponse do
  permit_params :user_id, :survey_question_id, :response

  index do
    selectable_column
    id_column
    column :user
    column :survey_question
    column :response
    column :created_at
    actions
  end

  filter :user
  filter :survey_question
  filter :response
  filter :created_at

  form do |f|
    f.inputs do
      f.input :user
      f.input :survey_question
      f.input :response
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :survey_question
      row :response
      row :created_at
      row :updated_at
    end
  end

  # Add this block to enable PDF download
  action_item :view, only: :index do
    link_to 'Download PDF', admin_survey_responses_path(format: 'pdf')
  end

  controller do
    def index
      super do |format|
        format.pdf do
          responses = SurveyResponse.includes(:user, :survey_question).all
          pdf = SurveyResponsesPdf.new(responses)
          send_data pdf.render, filename: "survey_responses.pdf",
                                type: "application/pdf",
                                disposition: "inline"
        end
      end
    end
  end
end
