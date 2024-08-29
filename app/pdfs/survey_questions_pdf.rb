class SurveyQuestionsPdf < Prawn::Document
  def initialize(questions)
    super(page_size: "A4", page_layout: :landscape)
    @questions = questions
    generate_content
  end

  def generate_content
    text "Survey Questions Report", size: 18, style: :bold, align: :center
    move_down 20
    questions_table
  end

  def questions_table
    table question_rows do
      row(0).font_style = :bold
      self.header = true
      self.row_colors = ['DDDDDD', 'FFFFFF']
      self.cell_style = { size: 10, padding: [3, 3, 3, 3] }
      self.width = 720
    end
  end

  def question_rows
    [['ID', 'Question Text', 'Question Type', 'Created At']] +
    @questions.map do |question|
      [
        question.id,
        question.question_text,
        question.question_type,
        question.created_at.strftime("%Y-%m-%d")
      ]
    end
  end
end
