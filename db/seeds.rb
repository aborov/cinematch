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

# Reset the attention check questions
puts "Resetting attention check questions..."
ActiveRecord::Base.connection.execute("DELETE FROM survey_questions WHERE question_type = 'attention_check'")
# or if you want to be more thorough:
# ActiveRecord::Base.connection.execute("DELETE FROM survey_questions WHERE question_type = 'attention_check' RETURNING id")

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
  { question_text: "I seek out new experiences.", question_type: "big5_openness_experience", survey_type: "basic" },
  { question_text: "I enjoy creative activities.", question_type: "big5_openness_creativity", survey_type: "basic" },
  { question_text: "I am interested in abstract ideas.", question_type: "big5_openness_ideas", survey_type: "basic" },

  { question_text: "I complete tasks methodically.", question_type: "big5_conscientiousness_orderliness", survey_type: "basic" },
  { question_text: "I pay attention to details.", question_type: "big5_conscientiousness_thoroughness", survey_type: "basic" },
  { question_text: "I follow plans consistently.", question_type: "big5_conscientiousness_reliability", survey_type: "basic" },

  { question_text: "I enjoy social gatherings.", question_type: "big5_extraversion_sociability", survey_type: "basic" },
  { question_text: "I start conversations easily.", question_type: "big5_extraversion_assertiveness", survey_type: "basic" },
  { question_text: "I energize others.", question_type: "big5_extraversion_energy", survey_type: "basic" },

  { question_text: "I empathize with others' feelings.", question_type: "big5_agreeableness_empathy", survey_type: "basic" },
  { question_text: "I care about others' well-being.", question_type: "big5_agreeableness_compassion", survey_type: "basic" },
  { question_text: "I cooperate with others.", question_type: "big5_agreeableness_cooperation", survey_type: "basic" },

  { question_text: "I handle stress well.", question_type: "big5_neuroticism_stability", survey_type: "basic" },
  { question_text: "I stay calm under pressure.", question_type: "big5_neuroticism_anxiety", survey_type: "basic" },
  { question_text: "I maintain emotional balance.", question_type: "big5_neuroticism_mood", survey_type: "basic" },

  # HEXACO Addition (6 questions)
  { question_text: "I remain truthful even at personal cost.", question_type: "hexaco_honesty", survey_type: "basic" },
  { question_text: "I avoid manipulating others.", question_type: "hexaco_sincerity", survey_type: "basic" },
  { question_text: "I treat everyone fairly.", question_type: "hexaco_fairness", survey_type: "basic" },
  { question_text: "I stay modest about achievements.", question_type: "hexaco_modesty", survey_type: "basic" },
  { question_text: "I avoid seeking attention.", question_type: "hexaco_greedavoidance", survey_type: "basic" },
  { question_text: "I value integrity over gain.", question_type: "hexaco_faithfulness", survey_type: "basic" },

  # Basic Emotional Intelligence (4 questions)
  { question_text: "I recognize others' emotions easily.", question_type: "ei_recognition", survey_type: "basic" },
  { question_text: "I manage my emotions well.", question_type: "ei_management", survey_type: "basic" },
  { question_text: "I understand emotional complexity.", question_type: "ei_understanding", survey_type: "basic" },
  { question_text: "I adapt to others' emotional needs.", question_type: "ei_adaptation", survey_type: "basic" },

  # Basic Attachment Style (5 questions)
  { question_text: "I trust others easily.", question_type: "attachment_trust", survey_type: "basic" },
  { question_text: "I maintain healthy boundaries.", question_type: "attachment_boundaries", survey_type: "basic" },
  { question_text: "I form close bonds comfortably.", question_type: "attachment_closeness", survey_type: "basic" },
  { question_text: "I rely on others when needed.", question_type: "attachment_dependence", survey_type: "basic" },
  { question_text: "I express feelings openly.", question_type: "attachment_expression", survey_type: "basic" }
]

# Extended Survey Questions (67 questions)
extended_survey_questions = [
  # Cognitive Style Assessment (12 questions)
  { question_text: "I prefer visual to written information.", question_type: "cognitive_visual_verbal", survey_type: "extended" },
  { question_text: "I solve problems step by step.", question_type: "cognitive_systematic", survey_type: "extended" },
  { question_text: "I enjoy theoretical discussions.", question_type: "cognitive_abstract", survey_type: "extended" },
  { question_text: "I need clear-cut answers.", question_type: "cognitive_closure", survey_type: "extended" },
  { question_text: "I learn through practical experience.", question_type: "cognitive_experiential", survey_type: "extended" },
  { question_text: "I notice subtle patterns.", question_type: "cognitive_pattern", survey_type: "extended" },
  { question_text: "I'm comfortable with ambiguity.", question_type: "cognitive_ambiguity", survey_type: "extended" },
  { question_text: "I prefer exploring multiple interpretations.", question_type: "cognitive_multiplicity", survey_type: "extended" },
  { question_text: "I enjoy complex narratives.", question_type: "cognitive_complexity", survey_type: "extended" },
  { question_text: "I process information holistically.", question_type: "cognitive_holistic", survey_type: "extended" },
  { question_text: "I adapt easily to unclear situations.", question_type: "cognitive_flexibility", survey_type: "extended" },
  { question_text: "I prefer structured information.", question_type: "cognitive_structure", survey_type: "extended" },

  # Extended Emotional Intelligence (8 questions)
  { question_text: "I seek emotionally challenging content.", question_type: "ei_challenge_seeking", survey_type: "extended" },
  { question_text: "I handle intense emotional content well.", question_type: "ei_intensity_tolerance", survey_type: "extended" },
  { question_text: "I use media to regulate emotions.", question_type: "ei_regulation_strategy", survey_type: "extended" },
  { question_text: "I process emotions through stories.", question_type: "ei_narrative_processing", survey_type: "extended" },
  { question_text: "I reflect on emotional experiences.", question_type: "ei_reflection", survey_type: "extended" },
  { question_text: "I learn from others' emotional journeys.", question_type: "ei_vicarious_learning", survey_type: "extended" },
  { question_text: "I balance emotion and reason.", question_type: "ei_integration", survey_type: "extended" },
  { question_text: "I recover quickly from emotional content.", question_type: "ei_resilience", survey_type: "extended" },

  # Values and Moral Foundations (15 questions)
  { question_text: "I protect the vulnerable.", question_type: "moral_care", survey_type: "extended" },
  { question_text: "I value equal treatment.", question_type: "moral_fairness", survey_type: "extended" },
  { question_text: "I maintain group loyalty.", question_type: "moral_loyalty", survey_type: "extended" },
  { question_text: "I respect authority.", question_type: "moral_authority", survey_type: "extended" },
  { question_text: "I value moral purity.", question_type: "moral_purity", survey_type: "extended" },
  { question_text: "I prioritize personal growth.", question_type: "moral_growth", survey_type: "extended" },
  { question_text: "I challenge established views.", question_type: "moral_challenge", survey_type: "extended" },
  { question_text: "I value self-direction.", question_type: "moral_autonomy", survey_type: "extended" },
  { question_text: "I preserve traditions.", question_type: "moral_tradition", survey_type: "extended" },
  { question_text: "I seek universal harmony.", question_type: "moral_universalism", survey_type: "extended" },
  { question_text: "I pursue achievement.", question_type: "moral_achievement", survey_type: "extended" },
  { question_text: "I value security.", question_type: "moral_security", survey_type: "extended" },
  { question_text: "I seek power responsibly.", question_type: "moral_power", survey_type: "extended" },
  { question_text: "I pursue hedonistic pleasures.", question_type: "moral_hedonism", survey_type: "extended" },
  { question_text: "I value social recognition.", question_type: "moral_recognition", survey_type: "extended" },

  # Dark Triad/Tetrad (8 questions)
  { question_text: "I appreciate complex villains in stories.", question_type: "dark_antihero", survey_type: "extended" },
  { question_text: "I enjoy stories about strategic manipulation.", question_type: "dark_machiavellianism", survey_type: "extended" },
  { question_text: "I'm drawn to characters who break social rules.", question_type: "dark_nonconformity", survey_type: "extended" },
  { question_text: "I appreciate dark humor in content.", question_type: "dark_humor", survey_type: "extended" },
  { question_text: "I enjoy watching power dynamics unfold.", question_type: "dark_power", survey_type: "extended" },
  { question_text: "I'm fascinated by psychological manipulation in plots.", question_type: "dark_psychology", survey_type: "extended" },
  { question_text: "I appreciate morally ambiguous storylines.", question_type: "dark_morality", survey_type: "extended" },
  { question_text: "I'm interested in revenge narratives.", question_type: "dark_revenge", survey_type: "extended" },

  # Narrative Transportation (12 questions)
  { question_text: "I lose track of time in stories.", question_type: "narrative_immersion", survey_type: "extended" },
  { question_text: "I identify with characters deeply.", question_type: "narrative_identification", survey_type: "extended" },
  { question_text: "I experience stories emotionally.", question_type: "narrative_emotional", survey_type: "extended" },
  { question_text: "I visualize story scenes vividly.", question_type: "narrative_visualization", survey_type: "extended" },
  { question_text: "I reflect on stories afterward.", question_type: "narrative_reflection", survey_type: "extended" },
  { question_text: "I enjoy complex plot structures.", question_type: "narrative_complexity", survey_type: "extended" },
  { question_text: "I appreciate non-linear storytelling.", question_type: "narrative_nonlinear", survey_type: "extended" },
  { question_text: "I connect stories to my life.", question_type: "narrative_personal", survey_type: "extended" },
  { question_text: "I enjoy multiple plot threads.", question_type: "narrative_multiple", survey_type: "extended" },
  { question_text: "I appreciate ambiguous endings.", question_type: "narrative_ambiguity", survey_type: "extended" },
  { question_text: "I enjoy character development.", question_type: "narrative_character", survey_type: "extended" },
  { question_text: "I value thematic depth.", question_type: "narrative_theme", survey_type: "extended" },

  # Psychological Needs (12 questions)
  { question_text: "I value personal autonomy.", question_type: "psych_autonomy", survey_type: "extended" },
  { question_text: "I seek competence growth.", question_type: "psych_competence", survey_type: "extended" },
  { question_text: "I desire deep connections.", question_type: "psych_relatedness", survey_type: "extended" },
  { question_text: "I use media for escape.", question_type: "psych_escapism", survey_type: "extended" },
  { question_text: "I process emotions through media.", question_type: "psych_catharsis", survey_type: "extended" },
  { question_text: "I seek intellectual stimulation.", question_type: "psych_cognition", survey_type: "extended" },
  { question_text: "I appreciate self-discovery stories.", question_type: "psych_selfdiscovery", survey_type: "extended" },
  { question_text: "I look for meaningful content.", question_type: "psych_meaning", survey_type: "extended" },
  { question_text: "I seek inspiration in stories.", question_type: "psych_inspiration", survey_type: "extended" },
  { question_text: "I value personal transformation.", question_type: "psych_transformation", survey_type: "extended" },
  { question_text: "I use stories for comfort.", question_type: "psych_comfort", survey_type: "extended" },
  { question_text: "I seek validation through content.", question_type: "psych_validation", survey_type: "extended" }
]

puts "Creating basic survey questions..."
create_questions(basic_survey_questions)

puts "Creating extended survey questions..."
create_questions(extended_survey_questions)

# Attention Check Questions
attention_check_questions = [
  { 
    question_text: "For this attention check, please select 'Agree'",
    question_type: "attention_check",
    survey_type: "basic",
    correct_answer: "Agree"
  },
  { 
    question_text: "For this attention check, please select 'Disagree'",
    question_type: "attention_check",
    survey_type: "basic",
    correct_answer: "Disagree"
  },
  { 
    question_text: "For this attention check, please select 'Neutral'",
    question_type: "attention_check",
    survey_type: "basic",
    correct_answer: "Neutral"
  }
]

puts "Creating attention check questions..."
attention_check_questions.each do |question_attrs|
  SurveyQuestion.find_or_create_by!(
    question_text: question_attrs[:question_text],
    question_type: question_attrs[:question_type],
    survey_type: question_attrs[:survey_type],
    correct_answer: question_attrs[:correct_answer]
  )
end

# Create admin user in development
# if Rails.env.development?
#   User.find_or_initialize_by(email: "alex@aborovikov.com").tap do |user|
#     user.name = "Aleksei"
#     user.password = ENV['ADMIN_PASSWORD']
#     user.password_confirmation = ENV['ADMIN_PASSWORD']
#     user.admin = true
#     user.save!
#   end
# end

puts "Seed completed successfully!"
