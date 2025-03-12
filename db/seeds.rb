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
    question = SurveyQuestion.find_or_initialize_by(
      question_text: question_attrs[:question_text],
      survey_type: question_attrs[:survey_type]
    )
    
    question.question_type = question_attrs[:question_type]
    question.inverted = question_attrs[:inverted] || false
    
    # Save the question with any changes
    question.save!
  end
  puts "Successfully processed questions batch"
rescue ActiveRecord::RecordInvalid => e
  puts "Error creating questions: #{e.message}"
  puts e.record.errors.full_messages
  raise e
end

# Basic Survey Questions (31 questions)
basic_survey_questions = [
  # Big Five (15 questions)
  { question_text: "I seek out new experiences.", question_type: "big5_openness_experience", survey_type: "basic" },
  { question_text: "I enjoy creative activities.", question_type: "big5_openness_creativity", survey_type: "basic" },
  { question_text: "I prefer familiar routines over new ideas.", question_type: "big5_openness_ideas", survey_type: "basic", inverted: true },

  { question_text: "I complete tasks thoroughly before moving on.", question_type: "big5_conscientiousness_orderliness", survey_type: "basic" },
  { question_text: "I pay attention to small details others might miss.", question_type: "big5_conscientiousness_thoroughness", survey_type: "basic" },
  { question_text: "I sometimes leave tasks unfinished.", question_type: "big5_conscientiousness_reliability", survey_type: "basic", inverted: true },

  { question_text: "I enjoy being the center of attention at social gatherings.", question_type: "big5_extraversion_sociability", survey_type: "basic" },
  { question_text: "I find it energizing to meet new people.", question_type: "big5_extraversion_assertiveness", survey_type: "basic" },
  { question_text: "I prefer quiet, solitary activities.", question_type: "big5_extraversion_energy", survey_type: "basic", inverted: true },

  { question_text: "I try to understand others' feelings even when I disagree.", question_type: "big5_agreeableness_empathy", survey_type: "basic" },
  { question_text: "I prioritize others' needs over my own.", question_type: "big5_agreeableness_compassion", survey_type: "basic" },
  { question_text: "I sometimes find it difficult to compromise.", question_type: "big5_agreeableness_cooperation", survey_type: "basic", inverted: true },

  { question_text: "Unexpected changes rarely upset me.", question_type: "big5_neuroticism_stability", survey_type: "basic", inverted: true },
  { question_text: "I remain composed in stressful situations.", question_type: "big5_neuroticism_anxiety", survey_type: "basic", inverted: true },
  { question_text: "I often worry about things that might go wrong.", question_type: "big5_neuroticism_mood", survey_type: "basic" },

  # HEXACO Honesty-Humility Factor (6 questions with inverted items)
  { question_text: "I remain truthful even when it's disadvantageous.", question_type: "hexaco_honesty", survey_type: "basic" },
  { question_text: "I would never flatter someone to get ahead.", question_type: "hexaco_sincerity", survey_type: "basic" },
  { question_text: "I sometimes bend rules for personal gain.", question_type: "hexaco_fairness", survey_type: "basic", inverted: true },
  { question_text: "I deserve more respect than the average person.", question_type: "hexaco_modesty", survey_type: "basic", inverted: true },
  { question_text: "Luxury goods give me pleasure.", question_type: "hexaco_greedavoidance", survey_type: "basic", inverted: true },
  { question_text: "I would never take things that aren't mine.", question_type: "hexaco_faithfulness", survey_type: "basic" },

  # Basic Emotional Intelligence (4 questions)
  { question_text: "I can identify subtle emotions in characters' expressions while watching shows.", question_type: "ei_recognition", survey_type: "basic" },
  { question_text: "I can watch emotionally intense content without becoming overwhelmed.", question_type: "ei_management", survey_type: "basic" },
  { question_text: "I understand why characters feel conflicting emotions in complex situations.", question_type: "ei_understanding", survey_type: "basic" },
  { question_text: "I find it hard to connect with characters whose emotional reactions differ from mine.", question_type: "ei_adaptation", survey_type: "basic", inverted: true },

  # Basic Attachment Style (6 questions with 2 dimensions: anxiety and avoidance)
  # Anxiety dimension (worry about abandonment)
  { question_text: "I worry that others won't care about me as much as I care about them.", question_type: "attachment_anxiety_worry", survey_type: "basic" },
  { question_text: "I need frequent reassurance that I am loved.", question_type: "attachment_anxiety_reassurance", survey_type: "basic" },
  { question_text: "I rarely worry about being abandoned by those close to me.", question_type: "attachment_anxiety_security", survey_type: "basic", inverted: true },

  # Avoidance dimension (discomfort with closeness)
  { question_text: "I prefer not to depend on others.", question_type: "attachment_avoidance_independence", survey_type: "basic" },
  { question_text: "I find it difficult to truly trust others.", question_type: "attachment_avoidance_trust", survey_type: "basic" },
  { question_text: "I'm comfortable being close to others.", question_type: "attachment_avoidance_closeness", survey_type: "basic", inverted: true },

  # Extended Emotional Intelligence (8 questions with balanced inverted items)
  { question_text: "I actively seek out films that challenge me emotionally.", question_type: "ei_challenge_seeking", survey_type: "extended" },
  { question_text: "I prefer to avoid movies with intense emotional scenes.", question_type: "ei_intensity_tolerance", survey_type: "extended", inverted: true },
  { question_text: "I choose different types of entertainment based on my current mood.", question_type: "ei_regulation_strategy", survey_type: "extended" },
  { question_text: "I find it hard to stop thinking about emotional scenes from movies.", question_type: "ei_resilience", survey_type: "extended", inverted: true },
  { question_text: "I can identify complex emotional nuances in film characters.", question_type: "ei_narrative_processing", survey_type: "extended" },
  { question_text: "I often analyze why characters respond emotionally the way they do.", question_type: "ei_reflection", survey_type: "extended" },
  { question_text: "Seeing characters work through emotional challenges helps me with my own.", question_type: "ei_vicarious_learning", survey_type: "extended" },
  { question_text: "I rarely connect characters' emotional experiences to my own life.", question_type: "ei_integration", survey_type: "extended", inverted: true },

  # Moral Foundations (10 questions covering 5 foundations with balanced items)
  # Care/Harm
  { question_text: "I feel strong compassion for people who are suffering.", question_type: "moral_care_compassion", survey_type: "extended" },
  { question_text: "Some people are too sensitive about harm to others.", question_type: "moral_care_sensitivity", survey_type: "extended", inverted: true },

  # Fairness/Cheating
  { question_text: "Justice and equality are the most important requirements for a society.", question_type: "moral_fairness_justice", survey_type: "extended" },
  { question_text: "Some level of inequality is necessary in a functioning society.", question_type: "moral_fairness_inequality", survey_type: "extended", inverted: true },

  # Loyalty/Betrayal
  { question_text: "Loyalty to one's group is more important than individual desires.", question_type: "moral_loyalty_group", survey_type: "extended" },
  { question_text: "People should make their own choices even if it goes against group expectations.", question_type: "moral_loyalty_individual", survey_type: "extended", inverted: true },

  # Authority/Subversion
  { question_text: "Respect for authority is an important virtue.", question_type: "moral_authority_respect", survey_type: "extended" },
  { question_text: "People should question traditions and authority.", question_type: "moral_authority_question", survey_type: "extended", inverted: true },

  # Sanctity/Degradation
  { question_text: "Certain acts are wrong regardless of their consequences.", question_type: "moral_purity_absolute", survey_type: "extended" },
  { question_text: "Moral standards should adapt to changing circumstances.", question_type: "moral_purity_relative", survey_type: "extended", inverted: true },

  # Dark Triad in Media Preferences (8 questions organized by trait)
  # Machiavellianism
  { question_text: "I enjoy watching characters who strategically manipulate others to achieve their goals.", question_type: "dark_machiavellianism_strategy", survey_type: "extended" },
  { question_text: "I find psychological manipulation in plots intellectually stimulating.", question_type: "dark_machiavellianism_plots", survey_type: "extended" },

  # Narcissism
  { question_text: "I am drawn to powerful, charismatic characters who command attention.", question_type: "dark_narcissism_power", survey_type: "extended" },
  { question_text: "I enjoy seeing exceptional individuals who aren't bound by ordinary social rules.", question_type: "dark_narcissism_exceptional", survey_type: "extended" },

  # Psychopathy
  { question_text: "I find myself fascinated by characters who act without emotional attachment.", question_type: "dark_psychopathy_emotion", survey_type: "extended" },
  { question_text: "Scenes of calculated revenge in films can be satisfying to watch.", question_type: "dark_psychopathy_revenge", survey_type: "extended" },

  # General Dark Appeal
  { question_text: "I prefer stories with morally complex antiheroes over clear-cut heroes.", question_type: "dark_general_antihero", survey_type: "extended" },
  { question_text: "I'm drawn to dark or gritty content that explores the shadowy sides of human nature.", question_type: "dark_general_gritty", survey_type: "extended" },

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
  { question_text: "I seek validation through content.", question_type: "psych_validation", survey_type: "extended" },
]

# Extended Survey Questions (59 questions)
extended_survey_questions = [
  # Cognitive Style Assessment (12 questions)
  { question_text: "I prefer visual to written information.", question_type: "cognitive_visual", survey_type: "extended" },
  { question_text: "I learn best through reading detailed descriptions.", question_type: "cognitive_verbal", survey_type: "extended" },
  { question_text: "I solve problems step by step.", question_type: "cognitive_systematic", survey_type: "extended" },
  { question_text: "I rely on intuition when making decisions.", question_type: "cognitive_intuitive", survey_type: "extended" },
  { question_text: "I enjoy theoretical discussions.", question_type: "cognitive_abstract", survey_type: "extended" },
  { question_text: "I prefer practical, real-world examples.", question_type: "cognitive_concrete", survey_type: "extended" },
  { question_text: "I need clear-cut answers.", question_type: "cognitive_certainty", survey_type: "extended" },
  { question_text: "I'm comfortable with ambiguity.", question_type: "cognitive_ambiguity", survey_type: "extended" },
  { question_text: "I learn through practical experience.", question_type: "cognitive_experiential", survey_type: "extended" },
  { question_text: "I prefer exploring concepts before experiencing them.", question_type: "cognitive_conceptual", survey_type: "extended" },
  { question_text: "I notice subtle details others might miss.", question_type: "cognitive_detail", survey_type: "extended" },
  { question_text: "I tend to see the big picture rather than small details.", question_type: "cognitive_pattern", survey_type: "extended" },

  # Extended Emotional Intelligence (8 questions with balanced inverted items)
  { question_text: "I actively seek out films that challenge me emotionally.", question_type: "ei_challenge_seeking", survey_type: "extended" },
  { question_text: "I prefer to avoid movies with intense emotional scenes.", question_type: "ei_intensity_tolerance", survey_type: "extended", inverted: true },
  { question_text: "I choose different types of entertainment based on my current mood.", question_type: "ei_regulation_strategy", survey_type: "extended" },
  { question_text: "I find it hard to stop thinking about emotional scenes from movies.", question_type: "ei_resilience", survey_type: "extended", inverted: true },
  { question_text: "I can identify complex emotional nuances in film characters.", question_type: "ei_narrative_processing", survey_type: "extended" },
  { question_text: "I often analyze why characters respond emotionally the way they do.", question_type: "ei_reflection", survey_type: "extended" },
  { question_text: "Seeing characters work through emotional challenges helps me with my own.", question_type: "ei_vicarious_learning", survey_type: "extended" },
  { question_text: "I rarely connect characters' emotional experiences to my own life.", question_type: "ei_integration", survey_type: "extended", inverted: true },

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

  # Narrative Transportation (8 questions with key dimensions)
  # Immersion
  { question_text: "I become so absorbed in movies that I lose track of time.", question_type: "narrative_immersion_time", survey_type: "extended" },
  { question_text: "I often find my mind wandering during films.", question_type: "narrative_immersion_focus", survey_type: "extended", inverted: true },

  # Character Identification
  { question_text: "I experience strong emotions when characters do.", question_type: "narrative_identification_emotion", survey_type: "extended" },
  { question_text: "I rarely see myself in fictional characters.", question_type: "narrative_identification_self", survey_type: "extended", inverted: true },

  # Narrative Complexity
  { question_text: "I enjoy films with multiple plot lines that come together.", question_type: "narrative_complexity_plots", survey_type: "extended" },
  { question_text: "I prefer straightforward stories over complex narratives.", question_type: "narrative_complexity_simple", survey_type: "extended", inverted: true },

  # Mental Imagery
  { question_text: "I create vivid mental images when engaging with stories.", question_type: "narrative_imagery_vivid", survey_type: "extended" },
  { question_text: "I enjoy stories that leave certain elements to the imagination.", question_type: "narrative_imagery_imagination", survey_type: "extended" },

  # Psychological Needs (SDT + Media-specific needs, 8 questions)
  # Autonomy
  { question_text: "I prefer stories where characters make their own choices.", question_type: "psych_autonomy_choice", survey_type: "extended" },
  { question_text: "I enjoy watching characters who rebel against restrictions.", question_type: "psych_autonomy_rebellion", survey_type: "extended" },

  # Competence
  { question_text: "I'm drawn to characters who master difficult skills.", question_type: "psych_competence_mastery", survey_type: "extended" },
  { question_text: "I find satisfaction in watching characters solve complex problems.", question_type: "psych_competence_problem", survey_type: "extended" },

  # Relatedness
  { question_text: "I value stories that explore meaningful relationships.", question_type: "psych_relatedness_connection", survey_type: "extended" },
  { question_text: "I'm moved by themes of belonging and acceptance in films.", question_type: "psych_relatedness_belonging", survey_type: "extended" },

  # Media-specific needs
  { question_text: "I use media as an escape from everyday concerns.", question_type: "psych_media_escape", survey_type: "extended" },
  { question_text: "I seek inspiration and motivation from the content I watch.", question_type: "psych_media_inspiration", survey_type: "extended" }
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
    correct_answer: "Agree",
  },
  {
    question_text: "For this attention check, please select 'Disagree'",
    question_type: "attention_check",
    survey_type: "basic",
    correct_answer: "Disagree",
  },
  {
    question_text: "For this attention check, please select 'Neutral'",
    question_type: "attention_check",
    survey_type: "basic",
    correct_answer: "Neutral",
  },
]

puts "Creating attention check questions..."
attention_check_questions.each do |question_attrs|
  SurveyQuestion.find_or_create_by!(
    question_text: question_attrs[:question_text],
    question_type: question_attrs[:question_type],
    survey_type: question_attrs[:survey_type],
    correct_answer: question_attrs[:correct_answer],
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
