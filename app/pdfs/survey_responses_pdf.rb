class SurveyResponsesPdf < Prawn::Document
  def initialize(responses)
    super(page_size: "A4", page_layout: :landscape)
    @responses = responses
    generate_content
  end

  def generate_content
    text "Survey Responses Report", size: 18, style: :bold, align: :center
    move_down 20
    responses_table
  end

  def responses_table
    table response_rows do
      row(0).font_style = :bold
      self.header = true
      self.row_colors = ['DDDDDD', 'FFFFFF']
      self.cell_style = { size: 10, padding: [3, 3, 3, 3] }
      self.width = 720
    end
  end

  def response_rows
    [['ID', 'User', 'Question', 'Response', 'Created At']] +
    @responses.map do |response|
      [
        response.id,
        response.user&.name || 'N/A',
        response.survey_question&.question_text || 'N/A',
        response.response,
        response.created_at.strftime("%Y-%m-%d")
      ]
    end
  end
end
