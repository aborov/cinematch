# frozen_string_literal: true

class PersonalityProfileService
  def self.generate_profile(user)
    new(user).generate_profile
  end

  def initialize(user)
    @user = user
  end

  def generate_profile
    {
      big_five: calculate_big_five_scores,
      emotional_intelligence: calculate_emotional_intelligence_scores,
      extended_traits: calculate_extended_traits_scores
    }
  end

  private

  def calculate_big_five_scores
    {
      openness: calculate_trait_score('big5_openness'),
      conscientiousness: calculate_trait_score('big5_conscientiousness'),
      extraversion: calculate_trait_score('big5_extraversion'),
      agreeableness: calculate_trait_score('big5_agreeableness'),
      neuroticism: calculate_trait_score('big5_neuroticism')
    }
  end

  def calculate_emotional_intelligence_scores
    {
      recognition: calculate_trait_score('ei_recognition'),
      management: calculate_trait_score('ei_management'),
      understanding: calculate_trait_score('ei_understanding'),
      adaptation: calculate_trait_score('ei_adaptation')
    }
  end

  def calculate_extended_traits_scores
    {
      hexaco_honesty: calculate_trait_score('hexaco_honesty'),
      hexaco_emotionality: calculate_trait_score('hexaco_emotionality'),
      cognitive_analytical: calculate_trait_score('cognitive_analytical'),
      cognitive_creative: calculate_trait_score('cognitive_creative'),
      moral_care: calculate_trait_score('moral_care'),
      moral_fairness: calculate_trait_score('moral_fairness'),
      narrative_preference: calculate_trait_score('narrative_preference'),
      psychological_needs: calculate_trait_score('psychological_needs')
    }
  end

  def calculate_trait_score(trait_prefix)
    responses = @user.survey_responses
                    .joins(:survey_question)
                    .where("survey_questions.question_type LIKE ?", "#{trait_prefix}%")
                    .where.not(survey_questions: { question_type: 'attention_check' })

    return 0 if responses.empty?

    # Convert responses to 0-100 scale and round to nearest integer
    total_score = responses.sum { |r| r.response.to_i }
    max_possible = responses.count * 5.0 # 5 is max score per question
    ((total_score / max_possible) * 100).round
  end
end 
