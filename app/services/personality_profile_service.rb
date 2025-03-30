# frozen_string_literal: true

class PersonalityProfileService
  def self.generate_profile(user, force_recalculate = false)
    new(user).generate_profile(force_recalculate)
  end

  def initialize(user)
    @user = user
  end

  def generate_profile(force_recalculate = false)
    user_preference = @user.ensure_user_preference
    
    # Return cached profile if available and not forcing recalculation
    if !force_recalculate && user_preference.personality_profiles.present?
      Rails.logger.info("Using cached personality profile for user #{@user.id}")
      return user_preference.personality_profiles.symbolize_keys
    end
    
    Rails.logger.info("Calculating personality profile for user #{@user.id}")
    
    # Check if user has any survey responses first
    responses_count = @user.survey_responses.joins(:survey_question)
                          .where.not(survey_questions: { question_type: 'attention_check' })
                          .count
    
    if responses_count == 0
      Rails.logger.warn("User #{@user.id} has no survey responses, cannot generate profile")
      return nil
    end
    
    begin
      profile = {
        big_five: calculate_big_five_scores,
        emotional_intelligence: calculate_emotional_intelligence_scores,
        extended_traits: calculate_extended_traits_scores
      }
      
      # Store the profile in the user_preference
      user_preference.update(personality_profiles: profile)
      Rails.logger.info("Stored personality profile for user #{@user.id}")
      
      profile
    rescue => e
      Rails.logger.error("Error generating personality profile for user #{@user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  private

  def calculate_big_five_scores
    # Group questions by trait dimension
    dimensions = {
      openness: calculate_dimension_score('big5_openness'),
      conscientiousness: calculate_dimension_score('big5_conscientiousness'),
      extraversion: calculate_dimension_score('big5_extraversion'),
      agreeableness: calculate_dimension_score('big5_agreeableness'),
      neuroticism: calculate_dimension_score('big5_neuroticism')
    }
    
    # Add derived metadata
    dimensions[:personality_type] = determine_personality_type(dimensions)
    
    dimensions
  end

  def calculate_dimension_score(dimension_prefix)
    # Get all responses for this dimension, accounting for inverted questions
    responses = @user.survey_responses
                    .joins(:survey_question)
                    .where("survey_questions.question_type LIKE ?", "#{dimension_prefix}%")
                    .where.not(survey_questions: { question_type: 'attention_check' })
    
    return 0 if responses.empty?
    
    total_score = responses.sum do |r|
      score = r.response.to_i
      score = 6 - score if r.survey_question.inverted?
      score
    end
    
    # Convert to 0-100 scale
    max_possible = responses.count * 5.0
    ((total_score / max_possible) * 100).round
  end

  def determine_personality_type(dimensions)
    # Simplified example - could be expanded with more sophisticated typing
    traits = dimensions.keys
    dominant_traits = traits.select { |t| dimensions[t] > 70 }
    secondary_traits = traits.select { |t| dimensions[t] > 50 && dimensions[t] <= 70 }
    
    {
      dominant: dominant_traits,
      secondary: secondary_traits
    }
  end

  def calculate_emotional_intelligence_scores
    # Calculate individual EI components
    recognition = calculate_trait_score('ei_recognition')
    management = calculate_trait_score('ei_management')
    understanding = calculate_trait_score('ei_understanding')
    adaptation = calculate_trait_score('ei_adaptation')
    
    # Calculate composite score (scientific models typically weight understanding and management higher)
    composite_score = (recognition * 0.2 + management * 0.3 + understanding * 0.3 + adaptation * 0.2).round
    
    {
      emotional_recognition: recognition,
      emotional_management: management,
      emotional_understanding: understanding,
      emotional_adaptation: adaptation,
      composite_score: composite_score,
      ei_level: categorize_ei_level(composite_score)
    }
  end

  def categorize_ei_level(score)
    case score
    when 0..40 then "developing"
    when 41..70 then "moderate"
    when 71..85 then "strong"
    else "exceptional"
    end
  end

  def calculate_extended_traits_scores
    # For basic survey, we only include limited profile elements
    if @user.survey_responses.joins(:survey_question).where(survey_questions: {survey_type: 'extended'}).empty?
      return {
        hexaco: calculate_hexaco_scores,
        attachment_style: calculate_attachment_style,
        # Limited profile for basic survey users
        profile_depth: "basic"
      }
    end
    
    # For extended survey, include all elements
    {
      hexaco: calculate_hexaco_scores,
      attachment_style: calculate_attachment_style,
      cognitive: calculate_cognitive_profile,
      moral_foundations: calculate_moral_foundations,
      dark_triad: calculate_dark_triad_preferences,
      narrative: calculate_narrative_profile,
      psychological_needs: calculate_psychological_needs_profile,
      extended_emotional_intelligence: calculate_extended_emotional_intelligence,
      profile_depth: "extended",
      # Add metadata for tracking
      metadata: {
        generated_at: Time.current.iso8601,
        response_count: @user.survey_responses.count,
        version: "2.0"
      }
    }
  end

  def calculate_cognitive_profile
    # Calculate opposing dimensions
    visual_verbal = calculate_dimension_pair('cognitive_visual', 'cognitive_verbal')
    systematic_intuitive = calculate_dimension_pair('cognitive_systematic', 'cognitive_intuitive')
    abstract_concrete = calculate_dimension_pair('cognitive_abstract', 'cognitive_concrete')
    certainty_ambiguity = calculate_dimension_pair('cognitive_certainty', 'cognitive_ambiguity')
    detail_pattern = calculate_dimension_pair('cognitive_detail', 'cognitive_pattern')
    
    # Create array of dimension pairs with their scores and preferences
    dimension_pairs = [
      visual_verbal,
      systematic_intuitive,
      abstract_concrete,
      certainty_ambiguity,
      detail_pattern
    ]
    
    {
      visual_verbal: visual_verbal,
      systematic_intuitive: systematic_intuitive,
      abstract_concrete: abstract_concrete,
      certainty_ambiguity: certainty_ambiguity,
      detail_pattern: detail_pattern,
      primary_style: determine_primary_cognitive_style(dimension_pairs)
    }
  end

  def calculate_dimension_pair(dim1_prefix, dim2_prefix)
    dim1_score = calculate_trait_score(dim1_prefix)
    dim2_score = calculate_trait_score(dim2_prefix)
    
    # Return a single value ranging from -100 to 100
    # Negative values indicate preference for dim1, positive for dim2
    return { score: 0, preference: 'balanced' } if dim1_score == 0 && dim2_score == 0
    
    total = dim1_score + dim2_score
    normalized_score = ((dim2_score - dim1_score) / total.to_f * 100).round
    
    {
      score: normalized_score,
      preference: normalized_score.abs > 20 ? (normalized_score < 0 ? dim1_prefix : dim2_prefix) : 'balanced'
    }
  end

  def calculate_trait_score(trait_prefix)
    # Enhanced scoring method that accounts for inverted questions
    responses = @user.survey_responses
                    .joins(:survey_question)
                    .where("survey_questions.question_type LIKE ?", "#{trait_prefix}%")
                    .where.not(survey_questions: { question_type: 'attention_check' })

    return 0 if responses.empty?
    
    # Process responses, accounting for inverted questions
    processed_scores = responses.map do |r|
      score = r.response.to_i
      question = r.survey_question
      # Invert score for questions marked as inverted
      score = 6 - score if question.inverted?
      score
    end

    # Convert to 0-100 scale and round to nearest integer
    total_score = processed_scores.sum
    max_possible = responses.count * 5.0
    ((total_score / max_possible) * 100).round
  end

  def calculate_hexaco_scores
    # Overall Honesty-Humility score
    honesty_humility = calculate_trait_with_facets('hexaco', ['honesty', 'sincerity', 'fairness', 'modesty', 'greedavoidance', 'faithfulness'])
    
    # In the complete HEXACO model, we'd also calculate:
    # emotionality = calculate_trait_with_facets('hexaco_emotionality')
    # extraversion = calculate_trait_with_facets('hexaco_extraversion')
    # agreeableness = calculate_trait_with_facets('hexaco_agreeableness')
    # conscientiousness = calculate_trait_with_facets('hexaco_conscientiousness')
    # openness = calculate_trait_with_facets('hexaco_openness')
    
    {
      honesty_humility: honesty_humility,
      integrity_level: categorize_honesty_level(honesty_humility)
    }
  end

  def calculate_trait_with_facets(trait_prefix, facets = [])
    scores = {}
    
    # Calculate each facet if facets are provided
    if facets.any?
      facets.each do |facet|
        facet_score = calculate_trait_score("#{trait_prefix}_#{facet}")
        scores[facet.to_sym] = facet_score if facet_score > 0
      end
    end
    
    # Calculate overall trait score
    overall_score = calculate_trait_score(trait_prefix)
    
    # If we have facet scores but no direct trait questions, average the facets
    if overall_score == 0 && scores.values.any?
      overall_score = scores.values.sum / scores.values.size
    end
    
    scores[:overall] = overall_score
    scores
  end

  def categorize_honesty_level(score)
    case score
    when 0..30 then "opportunistic"
    when 31..50 then "pragmatic"
    when 51..75 then "principled"
    else "highly_principled"
    end
  end

  def calculate_attachment_style
    # Calculate the two key dimensions
    anxiety = calculate_trait_score_by_subtype('attachment_anxiety')
    avoidance = calculate_trait_score_by_subtype('attachment_avoidance')
    
    # Determine attachment style quadrant
    style = determine_attachment_style(anxiety, avoidance)
    
    {
      anxiety: anxiety,
      avoidance: avoidance,
      attachment_style: style,
      media_implications: attachment_media_implications(style)
    }
  end

  def calculate_trait_score_by_subtype(subtype_prefix)
    # Find all questions that start with this subtype prefix
    responses = @user.survey_responses
                    .joins(:survey_question)
                    .where("survey_questions.question_type LIKE ?", "#{subtype_prefix}_%")
    
    return 0 if responses.empty?
    
    processed_scores = responses.map do |r|
      score = r.response.to_i
      score = 6 - score if r.survey_question.inverted?
      score
    end
    
    total_score = processed_scores.sum
    max_possible = responses.count * 5.0
    ((total_score / max_possible) * 100).round
  end

  def determine_attachment_style(anxiety, avoidance)
    # Low on both dimensions = Secure
    # High anxiety, low avoidance = Preoccupied/Anxious
    # Low anxiety, high avoidance = Dismissive/Avoidant
    # High on both dimensions = Fearful-Avoidant/Disorganized
    
    anxiety_threshold = 50
    avoidance_threshold = 50
    
    if anxiety < anxiety_threshold && avoidance < avoidance_threshold
      "secure"
    elsif anxiety >= anxiety_threshold && avoidance < avoidance_threshold
      "anxious"
    elsif anxiety < anxiety_threshold && avoidance >= avoidance_threshold
      "avoidant"
    else
      "fearful_avoidant"
    end
  end

  def attachment_media_implications(style)
    case style
    when "secure"
      "You likely enjoy a wide range of content and can engage with emotional material without becoming overwhelmed."
    when "anxious"
      "You may be drawn to emotional and romantic narratives, and may become deeply invested in character relationships."
    when "avoidant"
      "You may prefer action or intellectually-focused content over emotional dramas, and might maintain emotional distance from characters."
    when "fearful_avoidant"
      "You might be drawn to complex narratives that explore both independence and connection, possibly with conflicted feelings about character attachments."
    end
  end

  def calculate_extended_emotional_intelligence
    # Calculate each dimension
    engagement = calculate_dimension_score_with_subtypes('ei', ['challenge_seeking', 'intensity_tolerance'])
    regulation = calculate_dimension_score_with_subtypes('ei', ['regulation_strategy', 'resilience'])
    understanding = calculate_dimension_score_with_subtypes('ei', ['narrative_processing', 'reflection'])
    empathy = calculate_dimension_score_with_subtypes('ei', ['vicarious_learning', 'integration'])
    
    # Calculate total score (weighted appropriately)
    total_score = (engagement + regulation + understanding * 1.5 + empathy * 1.5) / 5.0
    
    {
      emotional_engagement: engagement,
      emotional_regulation: regulation,
      emotional_understanding: understanding,
      empathic_learning: empathy,
      extended_ei_score: total_score.round,
      media_emotional_profile: determine_media_emotional_profile(engagement, regulation, understanding, empathy)
    }
  end

  def calculate_dimension_score_with_subtypes(prefix, subtypes)
    scores = subtypes.map do |subtype|
      calculate_trait_score("#{prefix}_#{subtype}")
    end
    
    # Average the non-zero scores
    valid_scores = scores.reject { |s| s == 0 }
    valid_scores.any? ? (valid_scores.sum / valid_scores.size.to_f).round : 0
  end

  def determine_media_emotional_profile(engagement, regulation, understanding, empathy)
    # Create a profile based on strongest and weakest dimensions
    dimensions = {
      "Emotional Engagement" => engagement,
      "Emotional Regulation" => regulation,
      "Emotional Understanding" => understanding,
      "Empathic Learning" => empathy
    }
    
    strongest = dimensions.max_by { |_, v| v }
    weakest = dimensions.min_by { |_, v| v }
    
    profile = "Your strongest emotional dimension when engaging with media is #{strongest[0]} (#{strongest[1]}%). "
    profile += "You might benefit from developing your #{weakest[0]} (#{weakest[1]}%) when watching films."
    
    profile
  end

  def calculate_moral_foundations
    # Calculate scores for each foundation
    care = calculate_moral_foundation_score('moral_care')
    fairness = calculate_moral_foundation_score('moral_fairness')
    loyalty = calculate_moral_foundation_score('moral_loyalty')
    authority = calculate_moral_foundation_score('moral_authority')
    purity = calculate_moral_foundation_score('moral_purity')
    
    # Determine liberal-conservative orientation
    # Research shows that liberals tend to prioritize care and fairness,
    # while conservatives more equally value all five foundations
    individualizing = (care + fairness) / 2.0
    binding = (loyalty + authority + purity) / 3.0
    moral_orientation = determine_moral_orientation(individualizing, binding)
    
    {
      care: care,
      fairness: fairness,
      loyalty: loyalty,
      authority: authority,
      purity: purity,
      individualizing_foundations: individualizing.round,
      binding_foundations: binding.round,
      moral_orientation: moral_orientation,
      content_preferences: moral_content_preferences(care, fairness, loyalty, authority, purity)
    }
  end

  def calculate_moral_foundation_score(foundation_prefix)
    # Find all questions related to this moral foundation
    responses = @user.survey_responses
                    .joins(:survey_question)
                    .where("survey_questions.question_type LIKE ?", "#{foundation_prefix}_%")
    
    return 0 if responses.empty?
    
    processed_scores = responses.map do |r|
      score = r.response.to_i
      score = 6 - score if r.survey_question.inverted?
      score
    end
    
    total_score = processed_scores.sum
    max_possible = responses.count * 5.0
    ((total_score / max_possible) * 100).round
  end

  def determine_moral_orientation(individualizing, binding)
    diff = individualizing - binding
    
    if diff > 20
      "progressive"
    elsif diff < -20
      "traditional"
    else
      "moderate"
    end
  end

  def moral_content_preferences(care, fairness, loyalty, authority, purity)
    preferences = []
    
    if care > 70
      preferences << "socially conscious dramas"
    end
    
    if fairness > 70
      preferences << "stories about justice and equality"
    end
    
    if loyalty > 70
      preferences << "films emphasizing family and group bonds"
    end
    
    if authority > 70
      preferences << "traditional narratives with clear moral structure"
    end
    
    if purity > 70
      preferences << "content with spiritual or transcendent themes"
    end
    
    if preferences.empty?
      "Your moral values suggest a balanced approach to different types of content."
    else
      "Based on your moral values, you might particularly enjoy " + preferences.join(", ") + "."
    end
  end

  def calculate_narrative_profile
    # Calculate dimensions of narrative engagement
    immersion = calculate_dimension_score_with_subtypes('narrative_immersion', ['time', 'focus'])
    identification = calculate_dimension_score_with_subtypes('narrative_identification', ['emotion', 'self'])
    complexity = calculate_dimension_score_with_subtypes('narrative_complexity', ['plots', 'simple'])
    imagery = calculate_dimension_score_with_subtypes('narrative_imagery', ['vivid', 'imagination'])
    
    # Overall transportation score (weighted)
    transportation_score = (immersion * 0.3 + identification * 0.3 + complexity * 0.2 + imagery * 0.2).round
    
    # Determine narrative style preference
    style_preference = determine_narrative_style(immersion, identification, complexity, imagery)
    
    {
      immersion: immersion,
      character_identification: identification,
      complexity_preference: complexity,
      mental_imagery: imagery,
      transportation_score: transportation_score,
      narrative_style_preference: style_preference,
      film_recommendations: narrative_film_recommendations(style_preference, transportation_score)
    }
  end

  def determine_narrative_style(immersion, identification, complexity, imagery)
    # Create a profile based on strongest dimensions
    if immersion > 70 && identification > 70
      if complexity > 70
        "immersive_complex"
      else
        "immersive_emotional"
      end
    elsif complexity > 70 && imagery > 70
      "visualized_complexity"
    elsif identification > 70
      "character_driven"
    elsif complexity > 70
      "plot_driven"
    else
      "balanced"
    end
  end

  def narrative_film_recommendations(style, score)
    base = "Based on your narrative preferences, you likely enjoy "
    
    if score < 40
      return "You may engage with media more analytically than emotionally, preferring content that doesn't demand deep immersion."
    end
    
    case style
    when "immersive_complex"
      base + "immersive, multilayered films like 'Inception', 'Cloud Atlas', or series like 'Dark'."
    when "immersive_emotional"
      base + "emotionally engaging character journeys like 'Manchester by the Sea', 'Marriage Story', or 'This Is Us'."
    when "visualized_complexity"
      base + "visually striking films with intricate plots like 'Blade Runner 2049', 'The Grand Budapest Hotel', or 'Arrival'."
    when "character_driven"
      base + "deep character studies like 'The Queen's Gambit', 'Breaking Bad', or 'Nomadland'."
    when "plot_driven"
      base + "well-crafted story arcs with engaging plots like 'The Prestige', 'Gone Girl', or 'Knives Out'."
    else
      base + "well-balanced films that combine engaging characters with interesting plots."
    end
  end

  def calculate_psychological_needs_profile
    # Calculate core SDT needs
    autonomy = calculate_dimension_score_with_subtypes('psych_autonomy', ['choice', 'rebellion'])
    competence = calculate_dimension_score_with_subtypes('psych_competence', ['mastery', 'problem'])
    relatedness = calculate_dimension_score_with_subtypes('psych_relatedness', ['connection', 'belonging'])
    
    # Calculate media-specific needs
    escapism = calculate_trait_score("psych_media_escape")
    inspiration = calculate_trait_score("psych_media_inspiration")
    
    # Determine primary psychological need
    primary_need = determine_primary_need(autonomy, competence, relatedness)
    
    # Calculate media function (escapist vs. eudaimonic)
    media_function = determine_media_function(escapism, inspiration)
    
    {
      autonomy: autonomy,
      competence: competence,
      relatedness: relatedness,
      escapism: escapism,
      inspiration: inspiration,
      primary_need: primary_need,
      media_function: media_function,
      content_alignment: needs_content_alignment(primary_need, media_function)
    }
  end

  def determine_primary_need(autonomy, competence, relatedness)
    needs = {
      "autonomy" => autonomy,
      "competence" => competence,
      "relatedness" => relatedness
    }
    
    highest_need = needs.max_by { |_, score| score }
    
    # Check if the highest is significantly higher than others
    if highest_need[1] >= 70 && highest_need[1] > (needs.values.sum - highest_need[1]) / 2.0 + 15
      highest_need[0]
    else
      "balanced"
    end
  end

  def determine_media_function(escapism, inspiration)
    if escapism > inspiration + 20
      "primarily_escapist"
    elsif inspiration > escapism + 20
      "primarily_eudaimonic"
    else
      "balanced_function"
    end
  end

  def needs_content_alignment(primary_need, media_function)
    need_recommendations = {
      "autonomy" => "films featuring independent characters who chart their own path, such as 'Into the Wild' or 'Captain Fantastic'",
      "competence" => "stories of skill mastery and achievement like 'Whiplash', 'The Queen's Gambit', or sports dramas",
      "relatedness" => "films exploring deep human connections like 'Lost in Translation', 'The Intouchables', or ensemble dramas",
      "balanced" => "well-rounded narratives that balance personal freedom, achievement, and connection"
    }
    
    function_flavor = {
      "primarily_escapist" => "You tend to use media as an escape, so you might prefer more entertaining and immersive versions of ",
      "primarily_eudaimonic" => "You seek meaning and growth through media, so you might prefer thought-provoking and inspiring versions of ",
      "balanced_function" => "You balance entertainment with meaning in your media choices, likely enjoying both lighter and deeper versions of "
    }
    
    function_flavor[media_function] + need_recommendations[primary_need] + "."
  end

  def calculate_dark_triad_preferences
    # Calculate scores for each dark trait in media preferences
    machiavellianism = calculate_dimension_score_with_subtypes('dark_machiavellianism', ['strategy', 'plots'])
    narcissism = calculate_dimension_score_with_subtypes('dark_narcissism', ['power', 'exceptional'])
    psychopathy = calculate_dimension_score_with_subtypes('dark_psychopathy', ['emotion', 'revenge'])
    general_dark = calculate_dimension_score_with_subtypes('dark_general', ['antihero', 'gritty'])
    
    # Calculate overall dark content preference
    overall_score = (machiavellianism + narcissism + psychopathy + general_dark) / 4.0
    
    # Determine primary dark trait preference
    primary_trait = determine_primary_dark_trait(machiavellianism, narcissism, psychopathy)
    
    {
      machiavellianism_appeal: machiavellianism,
      narcissism_appeal: narcissism,
      psychopathy_appeal: psychopathy,
      general_dark_appeal: general_dark,
      overall_dark_content_preference: overall_score.round,
      primary_dark_trait_appeal: primary_trait,
      content_recommendations: dark_content_recommendations(primary_trait, overall_score.round)
    }
  end

  def determine_primary_dark_trait(machiavellianism, narcissism, psychopathy)
    traits = {
      "machiavellianism" => machiavellianism,
      "narcissism" => narcissism,
      "psychopathy" => psychopathy
    }
    
    # Find highest trait with a score above 60
    high_traits = traits.select { |_, score| score >= 60 }
    return "balanced" if high_traits.empty?
    
    high_traits.max_by { |_, score| score }[0]
  end

  def dark_content_recommendations(primary_trait, overall_score)
    base_recommendation = "Based on your preferences, you might enjoy "
    
    if overall_score < 40
      return "You tend to prefer content with clearer moral frameworks and more traditional heroes."
    end
    
    case primary_trait
    when "machiavellianism"
      base_recommendation + "political thrillers, strategy-focused dramas, and shows about complex power dynamics like 'House of Cards' or 'Succession'."
    when "narcissism"
      base_recommendation + "character studies of charismatic but flawed protagonists like 'The Wolf of Wall Street' or 'American Psycho'."
    when "psychopathy"
      base_recommendation + "psychological thrillers, crime dramas, and shows that explore morally detached characters like 'Dexter' or 'You'."
    else
      base_recommendation + "complex character studies with morally ambiguous protagonists, psychological thrillers, and darker dramas."
    end
  end

  def determine_primary_cognitive_style(dimension_pairs)
    # Find the dimension with the strongest preference (furthest from 0)
    strongest_dimension = dimension_pairs.max_by { |dim| dim[:score].abs }
    
    return 'balanced' if strongest_dimension[:score].abs < 30
    
    # Return the preference from the strongest dimension
    strongest_dimension[:preference]
  end
end 
