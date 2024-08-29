ActiveAdmin.register SurveyQuestion do
  permit_params :question_text, :question_type

  index do
    selectable_column
    id_column
    column :question_text
    column :question_type
    actions
  end

  filter :question_text
  filter :question_type

  form do |f|
    f.inputs do
      f.input :question_text
      f.input :question_type, as: :select, collection: ['multiple_choice', 'open_ended']
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :question_text
      row :question_type
      row :created_at
      row :updated_at
    end
  end

  # Add this block to enable PDF download
  action_item :view, only: :index do
    link_to 'Download PDF', admin_survey_questions_path(format: 'pdf')
  end

  controller do
    def index
      super do |format|
        format.pdf do
          questions = SurveyQuestion.all
          pdf = SurveyQuestionsPdf.new(questions)
          send_data pdf.render, filename: "survey_questions.pdf",
                                type: "application/pdf",
                                disposition: "inline"
        end
      end
    end
  end
end
