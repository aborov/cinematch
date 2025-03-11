class PersonalityProfileCalculator
  def self.calculate(responses)
    new(responses).calculate
  end

  def initialize(responses)
    @responses = responses
  end

  def calculate
    # Define the traits and their corresponding prefixes in the database
    trait_prefixes = {
      'openness' => 'big5_openness',
      'conscientiousness' => 'big5_conscientiousness',
      'extraversion' => 'big5_extraversion',
      'agreeableness' => 'big5_agreeableness',
      'neuroticism' => 'big5_neuroticism'
    }
    
    profile = {}

    trait_prefixes.each do |trait, prefix|
      # Filter responses that match the prefix and are not attention checks
      trait_responses = @responses.select do |r| 
        r.survey_question.question_type.start_with?(prefix) && 
        r.survey_question.question_type != 'attention_check'
      end
      
      if trait_responses.any?
        Rails.logger.info "Found #{trait_responses.size} responses for trait: #{trait}"
        # Convert string responses to integers before calculating average
        average_score = trait_responses.map { |r| r.response.to_i }.sum / trait_responses.size.to_f
        profile[trait] = average_score.round(2)
      else
        Rails.logger.warn "No responses found for trait: #{trait} (prefix: #{prefix})"
      end
    end

    # Add emotional intelligence if available
    ei_prefixes = {
      'emotional_recognition' => 'ei_recognition',
      'emotional_management' => 'ei_management',
      'emotional_understanding' => 'ei_understanding',
      'emotional_adaptation' => 'ei_adaptation'
    }
    
    ei_profile = {}
    ei_prefixes.each do |trait, prefix|
      trait_responses = @responses.select do |r| 
        r.survey_question.question_type.start_with?(prefix) && 
        r.survey_question.question_type != 'attention_check'
      end
      
      if trait_responses.any?
        Rails.logger.info "Found #{trait_responses.size} responses for EI trait: #{trait}"
        average_score = trait_responses.map { |r| r.response.to_i }.sum / trait_responses.size.to_f
        ei_profile[trait] = average_score.round(2)
      end
    end
    
    profile['emotional_intelligence'] = ei_profile if ei_profile.any?
    
    Rails.logger.info "Calculated personality profile: #{profile.inspect}"
    profile
  end
end
