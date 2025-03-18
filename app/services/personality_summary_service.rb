class PersonalitySummaryService
  def self.generate_summary(user)
    return nil unless user.user_preference&.personality_profiles.present?
    
    # Check if we have a cached summary
    return user.user_preference.personality_summary if user.user_preference.personality_summary.present?
    
    # Generate a new summary
    profile = user.user_preference.personality_profiles
    model = user.user_preference.ai_model.presence || AiModelsConfig.default_model
    
    summary = get_ai_summary(profile, model)
    
    # Cache the summary in user preferences
    user.user_preference.update(personality_summary: summary)
    
    summary
  end
  
  private
  
  def self.get_ai_summary(profile, model)
    prompt = generate_prompt(profile)
    Rails.logger.info "AI Summary Prompt:\n#{prompt}"
    
    model_config = AiModelsConfig::MODELS[model]
    
    case model_config[:provider]
    when :gemini
      get_gemini_summary(prompt, model_config)
    when :openai
      get_openai_summary(prompt, model_config)
    when :anthropic
      get_anthropic_summary(prompt, model_config)
    when :ollama
      get_ollama_summary(prompt, model_config)
    when :together
      get_together_summary(prompt, model_config)
    else
      Rails.logger.error "Unsupported AI provider: #{model_config[:provider]}"
      default_summary(profile)
    end
  rescue => e
    Rails.logger.error "Error generating personality summary: #{e.message}"
    default_summary(profile)
  end
  
  def self.generate_prompt(profile)
    # Format personality data in a readable way
    personality_section = format_personality_section(profile)
    
    prompt = <<~PROMPT.strip
      Based on the user's psychological profile below, write a concise 2-3 sentence summary of their personality.
      The summary should be personalized, insightful, and highlight the most distinctive aspects of their personality.
      Focus on how their traits might influence their media preferences and viewing habits.
      Write in second person (using "you" and "your").

      #{personality_section}

      Return ONLY the summary text with no additional formatting or explanation.
    PROMPT
    
    Rails.logger.info "Generated AI prompt with #{prompt.size} characters"
    prompt
  end
  
  def self.format_personality_section(profile)
    return "User Profile: Limited personality data available" if profile.blank?
    
    sections = ["User Psychological Profile:"]
    
    # Format Big Five traits
    if profile[:big_five].present?
      big_five = profile[:big_five]
      sections << "- Big Five Personality:"
      sections << "  • Openness: #{big_five[:openness]}%"
      sections << "  • Conscientiousness: #{big_five[:conscientiousness]}%"
      sections << "  • Extraversion: #{big_five[:extraversion]}%"
      sections << "  • Agreeableness: #{big_five[:agreeableness]}%"
      sections << "  • Neuroticism: #{big_five[:neuroticism]}%"
    end
    
    # Format Emotional Intelligence
    if profile[:emotional_intelligence].present?
      ei = profile[:emotional_intelligence]
      sections << "- Emotional Intelligence:"
      ei.except(:composite_score, :ei_level).each do |trait, score|
        sections << "  • #{trait.to_s.gsub('_', ' ').titleize}: #{score}%"
      end
      
      if ei[:ei_level].present?
        sections << "  • Overall EI Level: #{ei[:ei_level].to_s.titleize} (#{ei[:composite_score]}%)"
      end
    end
    
    # Add extended traits if available
    if profile[:extended_traits].present?
      extended = profile[:extended_traits]
      
      # Add HEXACO information
      if extended[:hexaco].present?
        hexaco = extended[:hexaco]
        sections << "- HEXACO Honesty-Humility:"
        
        if hexaco[:honesty_humility].present? && hexaco[:honesty_humility][:overall].present?
          sections << "  • Overall Score: #{hexaco[:honesty_humility][:overall]}%"
          
          # Add facets if available
          hexaco[:honesty_humility].except(:overall).each do |facet, score|
            sections << "  • #{facet.to_s.titleize}: #{score}%"
          end
        end
        
        if hexaco[:integrity_level].present?
          sections << "  • Integrity Level: #{hexaco[:integrity_level].to_s.titleize}"
        end
      end
      
      # Add Attachment Style
      if extended[:attachment_style].present?
        attachment = extended[:attachment_style]
        sections << "- Attachment Style:"
        
        if attachment[:attachment_style].present?
          sections << "  • Style: #{attachment[:attachment_style].to_s.humanize}"
        end
        
        if attachment[:anxiety].present? && attachment[:avoidance].present?
          sections << "  • Attachment Anxiety: #{attachment[:anxiety]}%"
          sections << "  • Attachment Avoidance: #{attachment[:avoidance]}%"
        end
      end
      
      # Add Moral Foundations if available
      if extended[:moral_foundations].present?
        moral = extended[:moral_foundations]
        sections << "- Moral Foundations:"
        
        if moral[:moral_orientation].present?
          sections << "  • Moral Orientation: #{moral[:moral_orientation].to_s.humanize}"
        end
        
        # Add detailed moral foundations if available
        [:care, :fairness, :loyalty, :authority, :purity].each do |foundation|
          if moral[foundation].present?
            sections << "  • #{foundation.to_s.titleize}: #{moral[foundation]}%"
          end
        end
      end
    end
    
    sections.join("\n")
  end
  
  def self.get_openai_summary(prompt, config)
    client = OpenAI::Client.new(
      access_token: ENV.fetch('OPENAI_API_KEY'),
      request_timeout: 30
    )
    
    response = client.chat(
      parameters: {
        model: config[:api_name],
        messages: [{
          role: "system",
          content: "You are a personality analysis expert. Provide concise, insightful summaries."
        }, {
          role: "user",
          content: prompt
        }],
        temperature: 0.7,
        max_tokens: 150
      }
    )
    
    begin
      content = response.dig("choices", 0, "message", "content")
      Rails.logger.info "OpenAI Summary Response: #{content}"
      content.strip
    rescue => e
      Rails.logger.error "OpenAI API error: #{e.message}"
      default_summary(nil)
    end
  end
  
  def self.get_anthropic_summary(prompt, config)
    response = HTTP.headers(
      "x-api-key" => ENV.fetch('ANTHROPIC_API_KEY'),
      "anthropic-version" => "2023-06-01",
      "content-type" => "application/json"
    ).post("https://api.anthropic.com/v1/messages", json: {
      model: config[:api_name],
      max_tokens: 150,
      temperature: 0.7,
      system: "You are a personality analysis expert. Provide concise, insightful summaries.",
      messages: [{
        role: "user",
        content: prompt
      }]
    })
    
    begin
      result = JSON.parse(response.body.to_s)
      content = result.dig("content", 0, "text")
      Rails.logger.info "Claude Summary Response: #{content}"
      content.strip
    rescue => e
      Rails.logger.error "Claude API error: #{e.message}"
      default_summary(nil)
    end
  end
  
  def self.get_gemini_summary(prompt, config)
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
            text: "You are a personality analysis expert. Provide concise, insightful summaries."
          }]
        },
        generationConfig: {
          temperature: 0.7,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 150
        }
      }
    )

    begin
      result = JSON.parse(response.body.to_s)
      content = result.dig("candidates", 0, "content", "parts", 0, "text")
      Rails.logger.info "Gemini Summary Response: #{content}"
      content.strip
    rescue => e
      Rails.logger.error "Gemini API error: #{e.message}"
      default_summary(nil)
    end
  end
  
  def self.get_ollama_summary(prompt, config)
    response = HTTP.post("http://localhost:11434/api/generate", json: {
      model: config[:api_name],
      prompt: prompt,
      system: "You are a personality analysis expert. Provide concise, insightful summaries.",
      temperature: 0.7,
      max_tokens: 150
    })
    
    begin
      result = JSON.parse(response.body.to_s)
      content = result["response"]
      Rails.logger.info "Ollama Summary Response: #{content}"
      content.strip
    rescue => e
      Rails.logger.error "Ollama API error: #{e.message}"
      default_summary(nil)
    end
  end
  
  def self.get_together_summary(prompt, config)
    response = HTTP.headers(
      "Authorization" => "Bearer #{ENV.fetch('TOGETHER_API_KEY')}",
      "Content-Type" => "application/json"
    ).post("https://api.together.xyz/v1/chat/completions", json: {
      model: config[:api_name],
      messages: [{
        role: "system",
        content: "You are a personality analysis expert. Provide concise, insightful summaries."
      }, {
        role: "user",
        content: prompt
      }],
      temperature: 0.7,
      max_tokens: 150,
      top_p: 0.7,
      top_k: 50,
      repetition_penalty: 1,
      stream: false
    })

    begin
      result = JSON.parse(response.body.to_s)
      content = result.dig("choices", 0, "message", "content")
      Rails.logger.info "Together Summary Response: #{content}"
      content.strip
    rescue => e
      Rails.logger.error "Together API error: #{e.message}"
      default_summary(nil)
    end
  end
  
  def self.default_summary(profile)
    if profile.present? && profile[:big_five].present?
      big_five = profile[:big_five]
      
      traits = []
      traits << "open to new experiences" if big_five[:openness] > 70
      traits << "conscientious" if big_five[:conscientiousness] > 70
      traits << "extraverted" if big_five[:extraversion] > 70
      traits << "agreeable" if big_five[:agreeableness] > 70
      traits << "emotionally sensitive" if big_five[:neuroticism] > 70
      
      if traits.any?
        "You tend to be #{traits.join(', ')}. This likely influences your media preferences toward content that resonates with these aspects of your personality."
      else
        "Your personality profile shows a balanced mix of traits. You likely enjoy a diverse range of content that appeals to different aspects of your personality."
      end
    else
      "Your personality profile suggests you have a unique combination of traits that influence your media preferences. Complete more surveys to get a more detailed analysis."
    end
  end
end 
