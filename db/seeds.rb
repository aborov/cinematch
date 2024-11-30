# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

# User.create!(name: "John Doe", email: "john@example.com", password: "password", gender: "Male", dob: "1990-01-01")

# Reset the primary key sequence to ensure IDs start from 1
puts "Resetting survey questions..."
ActiveRecord::Base.connection.execute("TRUNCATE survey_questions RESTART IDENTITY")

# Helper method to create questions in batches
def create_questions(questions)
  questions.each do |question_attrs|
    SurveyQuestion.find_or_create_by!(
      question_text: question_attrs[:question_text],
      survey_type: question_attrs[:survey_type]
    ) do |q|
      q.question_type = question_attrs[:question_type]
    end
  end
  puts "Successfully processed questions batch"
rescue ActiveRecord::RecordInvalid => e
  puts "Error creating questions: #{e.message}"
  puts e.record.errors.full_messages
  raise e
end

# Basic Survey Questions (30 questions)
basic_survey_questions = [
  # Big Five (15 questions)
  # Openness (3)
  { question_text: "I enjoy trying new things.", question_type: "openness", survey_type: "basic" },
  { question_text: "I am imaginative and creative.", question_type: "openness", survey_type: "basic" },
  { question_text: "I enjoy thinking about abstract concepts.", question_type: "openness", survey_type: "basic" },
  
  # Conscientiousness (3)
  { question_text: "I am always prepared.", question_type: "conscientiousness", survey_type: "basic" },
  { question_text: "I pay attention to details.", question_type: "conscientiousness", survey_type: "basic" },
  { question_text: "I follow a schedule.", question_type: "conscientiousness", survey_type: "basic" },
  
  # Extraversion (3)
  { question_text: "I am the life of the party.", question_type: "extraversion", survey_type: "basic" },
  { question_text: "I feel comfortable around people.", question_type: "extraversion", survey_type: "basic" },
  { question_text: "I start conversations.", question_type: "extraversion", survey_type: "basic" },
  
  # Agreeableness (3)
  { question_text: "I am interested in people.", question_type: "agreeableness", survey_type: "basic" },
  { question_text: "I sympathize with others' feelings.", question_type: "agreeableness", survey_type: "basic" },
  { question_text: "I take time out for others.", question_type: "agreeableness", survey_type: "basic" },
  
  # Neuroticism (3)
  { question_text: "I get stressed out easily.", question_type: "neuroticism", survey_type: "basic" },
  { question_text: "I worry about things.", question_type: "neuroticism", survey_type: "basic" },
  { question_text: "I get upset easily.", question_type: "neuroticism", survey_type: "basic" },

  # HEXACO Addition (6 questions)
  { question_text: "I remain honest even when it might disadvantage me.", question_type: "honesty_humility", survey_type: "basic" },
  { question_text: "I avoid taking credit for others' achievements.", question_type: "honesty_humility", survey_type: "basic" },
  { question_text: "I believe everyone should be treated fairly.", question_type: "honesty_humility", survey_type: "basic" },
  { question_text: "I value integrity over personal gain.", question_type: "honesty_humility", survey_type: "basic" },
  { question_text: "I prefer modesty over showing off.", question_type: "honesty_humility", survey_type: "basic" },
  { question_text: "I avoid manipulating others for personal benefit.", question_type: "honesty_humility", survey_type: "basic" },

  # Basic Emotional Intelligence (4 questions)
  { question_text: "I easily recognize emotions in others.", question_type: "emotional_intelligence", survey_type: "basic" },
  { question_text: "I manage my emotions effectively.", question_type: "emotional_intelligence", survey_type: "basic" },
  { question_text: "I understand complex emotional situations.", question_type: "emotional_intelligence", survey_type: "basic" },
  { question_text: "I respond well to others' emotional needs.", question_type: "emotional_intelligence", survey_type: "basic" },

  # Basic Attachment Style (5 questions)
  { question_text: "I find it easy to depend on others.", question_type: "attachment", survey_type: "basic" },
  { question_text: "I rarely worry about being abandoned.", question_type: "attachment", survey_type: "basic" },
  { question_text: "I'm comfortable being emotionally close to others.", question_type: "attachment", survey_type: "basic" },
  { question_text: "I trust others to be there when needed.", question_type: "attachment", survey_type: "basic" },
  { question_text: "I prefer not to show my true feelings.", question_type: "attachment", survey_type: "basic" }
]

# Extended Survey Questions (70 questions)
extended_survey_questions = [
  # Detailed Big Five (25 questions, 5 additional per trait)
  
  # Openness
  { question_text: "I seek out intellectual challenges.", question_type: "openness", survey_type: "extended" },
  { question_text: "I enjoy exploring different art forms.", question_type: "openness", survey_type: "extended" },
  { question_text: "I like experiencing different cultures.", question_type: "openness", survey_type: "extended" },
  { question_text: "I enjoy unconventional ideas.", question_type: "openness", survey_type: "extended" },
  { question_text: "I value aesthetic experiences.", question_type: "openness", survey_type: "extended" },

  # Conscientiousness
  { question_text: "I complete tasks thoroughly.", question_type: "conscientiousness", survey_type: "extended" },
  { question_text: "I make plans and stick to them.", question_type: "conscientiousness", survey_type: "extended" },
  { question_text: "I take responsibilities seriously.", question_type: "conscientiousness", survey_type: "extended" },
  { question_text: "I prefer order and structure.", question_type: "conscientiousness", survey_type: "extended" },
  { question_text: "I think before acting.", question_type: "conscientiousness", survey_type: "extended" },

  # Extraversion
  { question_text: "I energize others around me.", question_type: "extraversion", survey_type: "extended" },
  { question_text: "I seek out social activities.", question_type: "extraversion", survey_type: "extended" },
  { question_text: "I enjoy being the center of attention.", question_type: "extraversion", survey_type: "extended" },
  { question_text: "I make friends easily.", question_type: "extraversion", survey_type: "extended" },
  { question_text: "I prefer group activities over solitary ones.", question_type: "extraversion", survey_type: "extended" },

  # Agreeableness
  { question_text: "I avoid conflicts with others.", question_type: "agreeableness", survey_type: "extended" },
  { question_text: "I consider others' feelings.", question_type: "agreeableness", survey_type: "extended" },
  { question_text: "I enjoy helping others.", question_type: "agreeableness", survey_type: "extended" },
  { question_text: "I forgive easily.", question_type: "agreeableness", survey_type: "extended" },
  { question_text: "I believe in cooperation over competition.", question_type: "agreeableness", survey_type: "extended" },

  # Neuroticism
  { question_text: "I experience mood swings.", question_type: "neuroticism", survey_type: "extended" },
  { question_text: "I am easily discouraged.", question_type: "neuroticism", survey_type: "extended" },
  { question_text: "I often feel overwhelmed.", question_type: "neuroticism", survey_type: "extended" },
  { question_text: "I worry about the future.", question_type: "neuroticism", survey_type: "extended" },
  { question_text: "I am sensitive to criticism.", question_type: "neuroticism", survey_type: "extended" },

  # Cognitive Style Assessment (10 questions)
  { question_text: "I prefer visual explanations over written ones.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I like solving problems systematically.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I enjoy abstract thinking.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I prefer clear, definitive answers.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I learn better through practical experience.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I enjoy analyzing complex problems.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I prefer structured learning environments.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I think in terms of pictures rather than words.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I enjoy discovering patterns in information.", question_type: "cognitive_style", survey_type: "extended" },
  { question_text: "I prefer multitasking over single-focus work.", question_type: "cognitive_style", survey_type: "extended" },

  # Values and Moral Foundations (15 questions)
  { question_text: "I believe in protecting the vulnerable.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value fairness above all else.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I am loyal to my social group.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I respect authority figures.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value traditional practices.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I believe in absolute moral truths.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I prioritize harm prevention.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value equal treatment for all.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I prioritize group harmony.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I respect hierarchical structures.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value purity in actions and thoughts.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I believe in justice over mercy.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value individual rights.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I believe in preserving social order.", question_type: "moral_foundations", survey_type: "extended" },
  { question_text: "I value spiritual cleanliness.", question_type: "moral_foundations", survey_type: "extended" },

  # Dark Triad/Tetrad (12 questions)
  { question_text: "I enjoy having power over others.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I believe most people can be manipulated.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I deserve more recognition than others.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I often feel little remorse.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I like to get revenge on authorities.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I enjoy outsmarting others.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I seek admiration from others.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I can be cunning when I need to be.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I enjoy seeing others struggle.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I tend to exploit others' weaknesses.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I believe I'm more capable than most people.", question_type: "dark_triad", survey_type: "extended" },
  { question_text: "I enjoy dominating debates or discussions.", question_type: "dark_triad", survey_type: "extended" },

  # Narrative Transportation (8 questions)
  { question_text: "I lose track of time when engaged in a story.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I easily identify with fictional characters.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I get emotionally involved in stories.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I vividly imagine story scenes.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I continue thinking about stories after they end.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I enjoy being immersed in fictional worlds.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I relate stories to my own experiences.", question_type: "narrative_transportation", survey_type: "extended" },
  { question_text: "I feel transformed by powerful stories.", question_type: "narrative_transportation", survey_type: "extended" },

  # Detailed Attachment Style (8 questions)
  # Secure Attachment
  { question_text: "I find it natural to form deep emotional connections with others.", question_type: "attachment_secure", survey_type: "extended" },
  { question_text: "I can rely on others while maintaining my independence.", question_type: "attachment_secure", survey_type: "extended" },

  # Anxious Attachment
  { question_text: "I often worry that others don't value me as much as I value them.", question_type: "attachment_anxious", survey_type: "extended" },
  { question_text: "I need frequent reassurance in my relationships.", question_type: "attachment_anxious", survey_type: "extended" },

  # Avoidant Attachment
  { question_text: "I prefer not to depend too much on others.", question_type: "attachment_avoidant", survey_type: "extended" },
  { question_text: "I maintain emotional distance to avoid getting hurt.", question_type: "attachment_avoidant", survey_type: "extended" },

  # Disorganized Attachment
  { question_text: "I have conflicting feelings about close relationships.", question_type: "attachment_disorganized", survey_type: "extended" },
  { question_text: "I both desire and fear deep emotional connections.", question_type: "attachment_disorganized", survey_type: "extended" }
]

puts "Creating basic survey questions..."
create_questions(basic_survey_questions)

puts "Creating extended survey questions..."
create_questions(extended_survey_questions)

# Create admin user in development
if Rails.env.development?
  User.find_or_initialize_by(email: "alex@aborovikov.com").tap do |user|
    user.name = "Aleksei"
    user.password = ENV['ADMIN_PASSWORD']
    user.password_confirmation = ENV['ADMIN_PASSWORD']
    user.admin = true
    user.save!
  end
end

puts "Seed completed successfully!"
