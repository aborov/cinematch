class AiRecommendationService
  def self.generate_recommendations(user_preference)
    Rails.logger.info "Starting recommendation generation for user #{user_preference.user_id}"
    
    model = user_preference.ai_model.presence || AiModelsConfig.default_model
    Rails.logger.info "Using AI model: #{model}"
    
    user_data = prepare_user_data(user_preference)
    response = get_ai_recommendations(user_data, model)
    process_recommendations(response, user_preference.disable_adult_content)
  end

  def self.preview_prompt(user_preference)
    user_data = prepare_user_data(user_preference)
    generate_prompt(user_data)
  end

  private

  def self.prepare_user_data(user_preference)
    model_config = AiModelsConfig::MODELS[user_preference.ai_model]
    
    # Determine token budget based on model capacity
    max_tokens = model_config[:max_tokens]
    
    # Allocate tokens for different parts of the prompt
    # Larger models get more detailed personality profiles and watch history
    token_allocation = calculate_token_allocation(max_tokens)
    
    # Get watch history with appropriate limits
    watched_items = user_preference.user.watchlist_items
      .where(watched: true)
      .where.not(rating: nil)
      .includes(:content)
      .order(rating: :desc, updated_at: :desc)
      .limit(token_allocation[:watch_history_items])

    high_rated, regular_rated = watched_items.partition { |item| item.rating >= 8 }
    
    # Calculate remaining slots based on model capacity
    remaining_slots = token_allocation[:watch_history_items] - high_rated.size
    regular_items_to_include = [remaining_slots, regular_rated.size].min

    {
      personality: extract_personality_data(user_preference.personality_profiles, token_allocation[:personality_depth]),
      favorite_genres: user_preference.favorite_genres,
      watched_history: {
        high_rated: format_items(high_rated, detailed: true),
        regular: format_items(regular_rated.first(regular_items_to_include), detailed: false)
      },
      profile_depth: user_preference.personality_profiles.dig(:extended_traits, :profile_depth) || "basic"
    }
  end

  def self.calculate_token_allocation(max_tokens)
    case max_tokens
    when 16384..Float::INFINITY # GPT-4o Mini and larger models
      {
        personality_depth: :full,
        watch_history_items: 150
      }
    when 8192..16383 # Gemini and Claude 3.5
      {
        personality_depth: :comprehensive,
        watch_history_items: 100
      }
    when 4000..8191 # GPT-3.5, Claude 3, DeepSeek
      {
        personality_depth: :moderate,
        watch_history_items: 50
      }
    else # Llama-3 and others
      {
        personality_depth: :basic,
        watch_history_items: 25
      }
    end
  end

  def self.extract_personality_data(profile, depth)
    return {} if profile.blank?
    
    # Always include basic profile data
    result = {
      big_five: profile[:big_five],
      emotional_intelligence: {
        ei_level: profile.dig(:emotional_intelligence, :ei_level),
        composite_score: profile.dig(:emotional_intelligence, :composite_score)
      }
    }
    
    # Add extended traits based on depth parameter
    if profile[:extended_traits].present?
      case depth
      when :full
        # Include all available data
        result[:extended_traits] = profile[:extended_traits]
      when :comprehensive
        # Include most important extended traits
        result[:extended_traits] = {
          profile_depth: profile.dig(:extended_traits, :profile_depth),
          hexaco: profile.dig(:extended_traits, :hexaco),
          attachment_style: profile.dig(:extended_traits, :attachment_style),
          moral_foundations: profile.dig(:extended_traits, :moral_foundations)
        }.compact
      when :moderate
        # Include only the most critical extended traits
        result[:extended_traits] = {
          profile_depth: profile.dig(:extended_traits, :profile_depth),
          hexaco: {
            integrity_level: profile.dig(:extended_traits, :hexaco, :integrity_level)
          },
          attachment_style: {
            attachment_style: profile.dig(:extended_traits, :attachment_style, :attachment_style)
          }
        }.compact
      when :basic
        # Include minimal extended data
        result[:extended_traits] = {
          profile_depth: profile.dig(:extended_traits, :profile_depth)
        }.compact
      end
    end
    
    result
  end

  def self.format_items(items, detailed:)
    items.map do |item|
      next unless item.content
      if detailed
        {
          t: item.content.title,
          y: item.content.release_year,
          r: item.rating,
          g: item.content.genre_ids_array,
          type: item.content.content_type
        }
      else
        {
          t: item.content.title,
          y: item.content.release_year,
          r: item.rating,
          type: item.content.content_type
        }
      end
    end.compact
  end

  def self.get_ai_recommendations(user_data, model)
    prompt = generate_prompt(user_data)
    Rails.logger.info "AI Prompt:\n#{prompt}"
    
    model_config = AiModelsConfig::MODELS[model]
    
    case model_config[:provider]
    when :gemini
      get_gemini_recommendations(prompt, model_config)
    when :openai
      get_openai_recommendations(prompt, model_config)
    when :anthropic
      get_anthropic_recommendations(prompt, model_config)
    when :ollama
      get_ollama_recommendations(prompt, model_config)
    when :together
      get_together_recommendations(prompt, model_config)
    else
      Rails.logger.error "Unsupported AI provider: #{model_config[:provider]}"
      []
    end
  end

  def self.get_openai_recommendations(prompt, config)
    client = OpenAI::Client.new(
      access_token: ENV.fetch('OPENAI_API_KEY'),
      request_timeout: 60
    )
    
    response = client.chat(
      parameters: {
        model: config[:api_name],
        messages: [{
          role: "system",
          content: "You are a recommendation system. Respond only with valid JSON."
        }, {
          role: "user",
          content: prompt
        }],
        temperature: config[:temperature],
        max_tokens: config[:max_tokens],
        response_format: { type: "json_object" }
      }
    )
    
    begin
      content = response.dig("choices", 0, "message", "content")
      Rails.logger.info "OpenAI Response: #{content}"
      parse_ai_response(content)
    rescue Faraday::TimeoutError => e
      Rails.logger.error "OpenAI request timed out: #{e.message}"
      []
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse OpenAI response: #{e.message}"
      []
    rescue StandardError => e
      Rails.logger.error "OpenAI API error: #{e.message}"
      Rails.logger.error "Response: #{response.inspect}"
      []
    end
  end

  def self.get_anthropic_recommendations(prompt, config)
    response = HTTP.headers(
      "x-api-key" => ENV.fetch('ANTHROPIC_API_KEY'),
      "anthropic-version" => "2023-06-01",
      "content-type" => "application/json"
    ).post("https://api.anthropic.com/v1/messages", json: {
      model: config[:api_name],
      max_tokens: config[:max_tokens],
      temperature: config[:temperature],
      system: "You are a recommendation system. Respond only with valid JSON.",
      messages: [{
        role: "user",
        content: prompt
      }]
    })
    
    begin
      result = JSON.parse(response.body.to_s)
      Rails.logger.info "Raw Claude Response: #{result.inspect}"
      
      # Extract text from the first content item
      content = result.dig("content", 0, "text")
      Rails.logger.info "Extracted content: #{content}"
      
      parse_ai_response(content)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Claude response: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    rescue StandardError => e
      Rails.logger.error "Claude API error: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    end
  end

  def self.get_ollama_recommendations(prompt, config)
    response = HTTP.post("http://localhost:11434/api/generate", json: {
      model: config[:api_name],
      prompt: prompt,
      system: "You are a recommendation system. Respond only with valid JSON.",
      temperature: config[:temperature]
    })
    
    parse_ai_response(response.body.to_s)
  end

  def self.get_gemini_recommendations(prompt, config)
    response = HTTP.headers(
      "Content-Type" => "application/json"
    ).post(
      "https://generativelanguage.googleapis.com/v1beta/models/#{config[:api_name]}:generateContent?key=#{ENV.fetch('GEMINI_API_KEY')}",
      json: {
        contents: [{
          role: "user",
          parts: [{
            text: prompt
          }]
        }],
        systemInstruction: {
          role: "system",
          parts: [{
            text: "You are a recommendation system. Respond only with valid JSON."
          }]
        },
        generationConfig: {
          temperature: config[:temperature],
          topK: 64,
          topP: 0.95,
          maxOutputTokens: config[:max_tokens],
          responseMimeType: "application/json"
        }
      }
    )

    begin
      result = JSON.parse(response.body.to_s)
      Rails.logger.info "Raw Gemini Response: #{result.inspect}"
      
      content = result.dig("candidates", 0, "content", "parts", 0, "text")
      Rails.logger.info "Extracted content: #{content}"
      
      parse_ai_response(content)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Gemini response: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    rescue StandardError => e
      Rails.logger.error "Gemini API error: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    end
  end

  def self.get_together_recommendations(prompt, config)
    is_deepseek = config[:api_name].include?('deepseek')
    # Ask for more recommendations while keeping history smaller
    prompt = prompt.gsub("exactly 50 NEW titles", "exactly 30 NEW titles")
    
    response = HTTP.headers(
      "Authorization" => "Bearer #{ENV.fetch('TOGETHER_API_KEY')}",
      "Content-Type" => "application/json"
    ).post("https://api.together.xyz/v1/chat/completions", json: {
      model: config[:api_name],
      messages: [{
        role: "system",
        content: if is_deepseek
          "You are a recommendation system. After analyzing the request, output ONLY valid JSON with exactly 30 recommendations. Format: {\"recommendations\":[{\"title\":\"Title\",\"type\":\"movie/tv\",\"year\":YYYY,\"reason\":\"brief reason WITHOUT mentioning confidence scores\",\"confidence_score\":1-100}]}"
        else
          "You are a recommendation system. Output ONLY valid JSON with exactly 30 recommendations. Format: {\"recommendations\":[{\"title\":\"Title\",\"type\":\"movie/tv\",\"year\":YYYY,\"reason\":\"brief reason WITHOUT mentioning confidence scores\",\"confidence_score\":1-100}]}"
        end
      }, {
        role: "user",
        content: prompt
      }],
      temperature: config[:temperature],
      max_tokens: [config[:max_tokens], 4096].min,
      top_p: 0.7,
      top_k: 50,
      repetition_penalty: 1,
      stop: is_deepseek ? ["</s>"] : ["</s>", "<|eot_id|>", "<|eom_id|>"],
      stream: false
    })

    begin
      result = JSON.parse(response.body.to_s)
      content = result.dig("choices", 0, "message", "content")
      Rails.logger.info "Raw content: #{content}"
      
      # Handle different model outputs
      content = if is_deepseek && content.include?("<think>")
        # Extract JSON after thinking process
        if content =~ /<think>.*?<\/think>\s*({.*})/m
          $1.strip
        else
          # If no JSON found after think tags, try to find any JSON
          content[/{.*}/m]&.strip
        end
      else
        # Standard JSON cleaning for Llama models
        content
          .gsub(/```json\s*/, '')
          .gsub(/```\s*/, '')
          .strip
      end

      Rails.logger.info "Cleaned content: #{content}"
      parsed = JSON.parse(content)
      parsed["recommendations"]
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Together response: #{e.message}"
      Rails.logger.error "Raw content after cleaning: #{content}"
      []
    rescue StandardError => e
      Rails.logger.error "Together API error for model #{config[:name]}: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    end
  end

  def self.parse_ai_response(content)
    return [] if content.blank?
    
    # Remove any markdown code block indicators if present
    content = content.gsub(/```json\n?/, '').gsub(/```\n?/, '')
    
    # Parse the JSON
    JSON.parse(content)["recommendations"]
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI response: #{e.message}"
    []
  end

  def self.generate_prompt(user_data)
    high_rated = user_data[:watched_history][:high_rated]
    regular = user_data[:watched_history][:regular]
    
    # Format watch history
    watch_history = [
      "Watch History (Highly Rated): " + high_rated.map { |w| "#{w[:t]} (#{w[:y]}, #{w[:type]}) - #{w[:r]}/10" }.join(" | "),
    ]
    
    if regular.any?
      watch_history << "Watch History (Other): " + regular.map { |w| "#{w[:t]} (#{w[:y]}, #{w[:type]}) - #{w[:r]}/10" }.join(" | ")
    end

    # Format personality data in a more readable way
    personality_section = format_personality_section(user_data[:personality], user_data[:profile_depth])
    
    # Create a more detailed prompt with specific instructions based on profile depth
    prompt = <<~PROMPT.strip
      Based on the user's detailed psychological profile and watch history below, recommend exactly 50 NEW titles that match their preferences. Each recommendation should include a confidence score (0-100) and a personalized reason that references specific aspects of their profile.

      Important guidelines:
      - Do NOT recommend any titles from the user's watch history
      - Provide diverse recommendations across different genres, not just their favorites
      - Include both movies and TV shows
      - For each recommendation, explain WHY it matches their psychological profile
      - Consider both conscious preferences (favorite genres) and psychological traits
      - Confidence scores should reflect how well the title matches their overall profile

      #{personality_section}

      Favorite Genres: #{user_data[:favorite_genres].join(', ')}

      #{watch_history.join("\n")}

      Return in this format: {"recommendations":[{"title":"exact title","type":"movie" or "tv","year":release year (integer),"reason":"brief explanation of why this matches their psychological profile WITHOUT mentioning confidence scores","confidence_score":integer between 0-100}]}
    PROMPT
    
    Rails.logger.info "Generated AI prompt with #{prompt.size} characters"
    prompt
  end

  def self.format_personality_section(personality, profile_depth)
    return "User Profile: Limited personality data available" if personality.blank?
    
    sections = ["User Psychological Profile:"]
    
    # Format Big Five traits
    if personality[:big_five].present?
      big_five = personality[:big_five]
      sections << "- Big Five Personality:"
      sections << "  • Openness: #{big_five[:openness]}% - #{describe_trait_level('Openness', big_five[:openness])}"
      sections << "  • Conscientiousness: #{big_five[:conscientiousness]}% - #{describe_trait_level('Conscientiousness', big_five[:conscientiousness])}"
      sections << "  • Extraversion: #{big_five[:extraversion]}% - #{describe_trait_level('Extraversion', big_five[:extraversion])}"
      sections << "  • Agreeableness: #{big_five[:agreeableness]}% - #{describe_trait_level('Agreeableness', big_five[:agreeableness])}"
      sections << "  • Neuroticism: #{big_five[:neuroticism]}% - #{describe_trait_level('Neuroticism', big_five[:neuroticism])}"
    end
    
    # Format Emotional Intelligence
    if personality[:emotional_intelligence].present?
      ei = personality[:emotional_intelligence]
      sections << "- Emotional Intelligence: #{ei[:ei_level]} (#{ei[:composite_score]}%)"
    end
    
    # Add extended traits if available
    if personality[:extended_traits].present?
      extended = personality[:extended_traits]
      
      # Add HEXACO information
      if extended[:hexaco].present?
        hexaco = extended[:hexaco]
        if hexaco[:honesty_humility].present? && hexaco[:honesty_humility][:overall].present?
          sections << "- Honesty-Humility: #{hexaco[:honesty_humility][:overall]}% (#{hexaco[:integrity_level]})"
        elsif hexaco[:integrity_level].present?
          sections << "- Integrity Level: #{hexaco[:integrity_level]}"
        end
      end
      
      # Add Attachment Style
      if extended[:attachment_style].present?
        attachment = extended[:attachment_style]
        if attachment[:attachment_style].present?
          sections << "- Attachment Style: #{attachment[:attachment_style].to_s.humanize}"
          if attachment[:anxiety].present? && attachment[:avoidance].present?
            sections << "  • Attachment Anxiety: #{attachment[:anxiety]}%"
            sections << "  • Attachment Avoidance: #{attachment[:avoidance]}%"
          end
        end
      end
      
      # Add Moral Foundations if available
      if extended[:moral_foundations].present?
        moral = extended[:moral_foundations]
        if moral[:moral_orientation].present?
          sections << "- Moral Orientation: #{moral[:moral_orientation].to_s.humanize}"
          
          # Add detailed moral foundations if available
          if moral[:care].present? && moral[:fairness].present?
            sections << "  • Care/Harm: #{moral[:care]}%"
            sections << "  • Fairness/Cheating: #{moral[:fairness]}%"
            sections << "  • Loyalty/Betrayal: #{moral[:loyalty]}%"
            sections << "  • Authority/Subversion: #{moral[:authority]}%"
            sections << "  • Purity/Degradation: #{moral[:purity]}%"
          end
        end
      end
      
      # Add Cognitive Style if available
      if extended[:cognitive].present?
        cognitive = extended[:cognitive]
        if cognitive[:primary_style].present?
          sections << "- Primary Cognitive Style: #{cognitive[:primary_style].to_s.humanize}"
        end
      end
    end
    
    # Add media implications based on profile depth
    sections << media_implications_section(personality, profile_depth)
    
    sections.join("\n")
  end
  
  def self.describe_trait_level(trait, score)
    case score
    when 0..20 then "Very Low"
    when 21..40 then "Low"
    when 41..60 then "Moderate"
    when 61..80 then "High"
    else "Very High"
    end
  end
  
  def self.media_implications_section(personality, profile_depth)
    return "" if personality.blank?
    
    implications = ["Content Preference Implications:"]
    
    # Add Big Five implications
    if personality[:big_five].present?
      big_five = personality[:big_five]
      
      if big_five[:openness] > 70
        implications << "- High openness suggests interest in science fiction, fantasy, and experimental content"
      elsif big_five[:openness] < 30
        implications << "- Low openness suggests preference for familiar, conventional content"
      end
      
      if big_five[:conscientiousness] > 70
        implications << "- High conscientiousness suggests interest in biographical, historical, and educational content"
      end
      
      if big_five[:extraversion] > 70
        implications << "- High extraversion suggests enjoyment of action, comedy, and adventure content"
      elsif big_five[:extraversion] < 30
        implications << "- Low extraversion suggests preference for thoughtful, introspective content"
      end
      
      if big_five[:neuroticism] > 70
        implications << "- High neuroticism may indicate interest in psychological thrillers and horror"
      end
      
      if big_five[:agreeableness] > 70
        implications << "- High agreeableness suggests enjoyment of heartwarming, family-oriented content"
      end
    end
    
    # Add extended trait implications if available
    if profile_depth == "extended" && personality[:extended_traits].present?
      extended = personality[:extended_traits]
      
      if extended[:attachment_style].present? && extended[:attachment_style][:attachment_style].present?
        case extended[:attachment_style][:attachment_style].to_s
        when "anxious"
          implications << "- Anxious attachment style suggests interest in relationship-focused narratives"
        when "avoidant"
          implications << "- Avoidant attachment style suggests preference for action-oriented content with less emotional focus"
        when "fearful_avoidant"
          implications << "- Fearful-avoidant attachment style suggests interest in complex narratives with both independence and connection themes"
        when "secure"
          implications << "- Secure attachment style suggests comfort with a wide range of emotional content"
        end
      end
      
      if extended[:hexaco].present? && extended[:hexaco][:integrity_level].present?
        case extended[:hexaco][:integrity_level].to_s
        when "highly_principled", "principled"
          implications << "- High integrity level suggests preference for content with clear moral messages"
        when "pragmatic", "opportunistic"
          implications << "- Pragmatic integrity level suggests interest in morally complex or ambiguous narratives"
        end
      end
    end
    
    implications.join("\n")
  end

  def self.process_recommendations(recommendations, disable_adult_content)
    Rails.logger.info "Processing #{recommendations.size} AI recommendations"
    
    content_ids = []
    reasons = {}
    match_scores = {}
    
    recommendations.each do |rec|
      begin
        Rails.logger.info "Processing recommendation: #{rec['title']} (#{rec['year']})"
        contents = find_all_content_versions(rec)
        next if contents.empty?
        
        # Filter adult content if needed
        contents = contents.reject(&:adult?) if disable_adult_content
        next if contents.empty?
        
        # Get best matching content
        content = if rec["year"] && (year_match = contents.find { |c| c.release_year == rec["year"] })
          year_match
        else
          contents.first
        end
        
        # Skip if already in our list
        next if content_ids.include?(content.id)
        
        # Get the reason and confidence score
        reason = rec["reason"].presence || "Matches user preferences"
        confidence = rec["confidence_score"].to_i
        
        # Clean the reason to remove any confidence scores
        # reason = clean_confidence_from_reason(reason)
        
        # Evaluate the quality of the reason and adjust confidence score if needed
        reason_quality = calculate_reason_quality_score(reason)
        
        # Calculate a genre match score as a sanity check
        genre_match = calculate_genre_match_score(content, reason)
        
        # Combine AI confidence with our quality metrics
        # This helps correct for overconfident or underconfident AI predictions
        adjusted_score = calculate_adjusted_score(confidence, reason_quality, genre_match)
        
        # Add to our results
        content_ids << content.id
        reasons[content.id.to_s] = reason
        match_scores[content.id.to_s] = adjusted_score
        
        Rails.logger.info "Added recommendation: #{content.title} (ID: #{content.id}) with score #{adjusted_score}"
      rescue => e
        Rails.logger.error "Error processing recommendation: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
    
    # Sort by score and return
    sorted_ids = content_ids.sort_by { |id| -match_scores[id.to_s].to_f }
    
    [sorted_ids, reasons, match_scores]
  end
  
  # def self.clean_confidence_from_reason(reason)
  #   return reason unless reason.present?
    
  #   # Remove confidence score patterns like "90% confidence", "confidence: 85%", etc.
  #   cleaned = reason.gsub(/\b(\d{1,3})%\s*(confidence|match|certainty|sure|confident)\b/i, '')
  #                  .gsub(/\b(confidence|match|certainty)(\s*:)?\s*(\d{1,3})%\b/i, '')
  #                  .gsub(/\bwith\s+(\d{1,3})%\s+(confidence|certainty|match)\b/i, '')
    
  #   # Remove standalone percentages at the end of the reason
  #   cleaned = cleaned.gsub(/\s*\(\s*\d{1,3}%\s*\)\s*$/, '')
  #                   .gsub(/\s*-\s*\d{1,3}%\s*$/, '')
  #                   .gsub(/\s*\[\s*\d{1,3}%\s*\]\s*$/, '')
    
  #   # Clean up any double spaces or trailing punctuation
  #   cleaned = cleaned.gsub(/\s{2,}/, ' ').strip
  #   cleaned = cleaned.gsub(/[,.:;]\s*$/, '')
    
  #   # If we've removed everything, return a default message
  #   cleaned.present? ? cleaned : "Matches user preferences"
  # end
  
  def self.calculate_adjusted_score(ai_confidence, reason_quality, genre_match)
    # Combine the scores with appropriate weights
    # - AI confidence: 50% (we trust the AI's judgment but want to verify)
    # - Reason quality: 30% (good explanations indicate better matches)
    # - Genre match: 20% (basic sanity check that genres align)
    
    weighted_score = (ai_confidence * 0.5) + (reason_quality * 0.3) + (genre_match * 0.2)
    
    # Ensure the score is within 0-100 range
    [weighted_score.round, 100].min
  end

  def self.calculate_genre_match_score(content, reason)
    return 50 unless reason.present? && content.genre_ids_array.present?
    
    # Extract genre mentions from reason
    mentioned_genres = Genre.all.map(&:name).select { |genre| reason.downcase.include?(genre.downcase) }
    
    # Calculate overlap with content's actual genres
    content_genres = Genre.where(tmdb_id: content.genre_ids_array).pluck(:name)
    matching_genres = (mentioned_genres & content_genres).size
    
    # Score based on genre match accuracy
    if matching_genres > 0
      base_score = 70 + (matching_genres * 10)
      [base_score, 100].min
    else
      50 # Default score when no genres match
    end
  end

  def self.calculate_reason_quality_score(reason)
    return 50 unless reason.present?
    
    score = 50 # base score
    
    # Check for psychological trait mentions
    psychological_terms = [
      # Big Five traits
      'openness', 'conscientiousness', 'extraversion', 'agreeableness', 'neuroticism',
      # Trait descriptions
      'creative', 'curious', 'organized', 'responsible', 'outgoing', 'sociable',
      'compassionate', 'cooperative', 'anxious', 'emotional', 'stability',
      # HEXACO
      'honesty', 'humility', 'integrity', 'principled',
      # Attachment styles
      'attachment', 'secure', 'anxious', 'avoidant', 'fearful',
      # Emotional intelligence
      'emotional intelligence', 'emotional awareness', 'empathy',
      # Moral foundations
      'moral', 'care', 'fairness', 'loyalty', 'authority', 'purity',
      # Cognitive styles
      'cognitive', 'visual', 'verbal', 'abstract', 'concrete', 'systematic', 'intuitive'
    ]
    
    # Boost for mentioning psychological traits (more specific than before)
    psychological_matches = psychological_terms.count { |term| reason.downcase.include?(term) }
    score += [psychological_matches * 5, 25].min # Cap at 25 points
    
    # Boost for mentioning user preferences
    preference_terms = [
      'preference', 'favorite', 'enjoys', 'liked', 'rated highly',
      'watch history', 'watched', 'enjoyed', 'appreciated', 'resonated'
    ]
    preference_matches = preference_terms.count { |term| reason.downcase.include?(term) }
    score += [preference_matches * 5, 15].min # Cap at 15 points
    
    # Boost for specific genre or content element mentions
    content_terms = [
      'genre', 'themes', 'narrative', 'character', 'plot', 'story',
      'visual', 'cinematography', 'acting', 'director', 'writing',
      'emotional', 'intellectual', 'philosophical', 'action', 'comedy',
      'drama', 'thriller', 'horror', 'romance', 'sci-fi', 'fantasy'
    ]
    content_matches = content_terms.count { |term| reason.downcase.include?(term) }
    score += [content_matches * 2, 10].min # Cap at 10 points
    
    # Boost for explanation quality
    if reason.length > 100
      score += 5 # Bonus for detailed explanations
    end
    
    # Penalize generic reasons
    generic_phrases = [
      'this matches', 'based on your', 'you might enjoy', 'you would like',
      'recommended for you', 'good match', 'great fit', 'perfect for'
    ]
    if generic_phrases.any? { |phrase| reason.downcase.include?(phrase) } && reason.length < 50
      score -= 10 # Penalty for short, generic reasons
    end
    
    # Cap at 100
    [score, 100].min
  end

  def self.find_all_content_versions(recommendation)
    # First try exact match with both source_id and content_type
    content_type = recommendation["type"] || 'movie'
    contents = Content.where(source_id: recommendation["source_id"], content_type: content_type)
    
    if contents.empty?
      # Try fuzzy title match if no exact match found
      contents = Content.where("LOWER(title) LIKE ?", "%#{recommendation["title"].downcase}%")
                       .where(content_type: content_type)
    end

    if contents.present?
      Rails.logger.info "Found matches in database: #{contents.size} versions"
      return contents if recommendation["year"].nil?
      
      # If year provided, filter by year
      if (year_match = contents.find { |c| c.release_year == recommendation["year"] })
        Rails.logger.info "Found year-specific match: #{year_match.title} (#{year_match.release_year})"
        return [year_match]
      end
    end

    # If no matches in database, try TMDB
    Rails.logger.info "No matches in database, searching TMDB..."
    tmdb_result = TmdbService.search({
      title: recommendation["title"],
      year: recommendation["year"],
      type: content_type
    })

    if tmdb_result
      Rails.logger.info "Found match in TMDB: #{tmdb_result['title'] || tmdb_result['name']} (ID: #{tmdb_result['id']})"
      require_relative '../../lib/tasks/tmdb_tasks'
      TmdbTasks.update_content_batch([tmdb_result])
      content = Content.find_by(source_id: tmdb_result['id'], content_type: content_type)
      return [content] if content
    end

    []
  end
end 
