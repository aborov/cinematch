class PersonalityProfileCalculator
  def self.calculate(responses)
    new(responses).calculate
  end

  def initialize(responses)
    @responses = responses
  end

  def calculate
    traits = %w[openness conscientiousness extraversion agreeableness neuroticism]
    profile = {}

    traits.each do |trait|
      trait_responses = @responses.select { |r| r.survey_question.question_type == trait }
      if trait_responses.any?
        average_score = trait_responses.map { |r| r.response.to_i }.sum / trait_responses.size.to_f
        profile[trait] = average_score.round(2)
      else
        Rails.logger.warn "No responses found for trait: #{trait}"
      end
    end

    profile
  end
end
