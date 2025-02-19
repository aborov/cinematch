class AiModelsConfig
  MODELS = {
    'gemini-2-flash' => {
      provider: :gemini,
      api_name: 'gemini-2.0-flash',
      name: 'Gemini 2.0 Flash',
      context_window: 1048576,
      max_tokens: 8192,
      temperature: 0.7,
      input_cost_per_1M: 0.1,
      output_cost_per_1M: 0.4,
      description: 'Fast and efficient, optimized for speed'
    },
    'gemini-2-pro-exp' => {
      provider: :gemini,
      api_name: 'gemini-2.0-pro-exp-02-05',
      name: 'Gemini 2.0 Pro (Experimental)',
      context_window: 2097152,
      max_tokens: 8192,
      temperature: 0.7,
      input_cost_per_1M: 0,
      output_cost_per_1M: 0,
      description: 'Enhanced capabilities for nuanced suggestions'
    },
    'gpt-4o-mini' => {
      provider: :openai,
      api_name: 'gpt-4o-mini',
      name: 'GPT-4o Mini',
      context_window: 128000,
      max_tokens: 16384,
      temperature: 0.7,
      input_cost_per_1M: 0.15,
      output_cost_per_1M: 0.6,
      description: 'Cost-effective with high-quality output'
    },
    'claude-3-5-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-5-haiku-latest',
      name: 'Claude 3.5 Haiku',
      context_window: 200000,
      max_tokens: 8192,
      temperature: 0.7,
      input_cost_per_1M: 0.8,
      output_cost_per_1M: 4.0,
      description: 'Rapid recommendations with high accuracy'
    },
    'claude-3-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-haiku-20240307',
      name: 'Claude 3 Haiku',
      context_window: 200000,
      max_tokens: 4096,
      temperature: 0.7,
      input_cost_per_1M: 0.25,
      output_cost_per_1M: 1.25,
      description: 'Quick performance for instant results'
    },
    'llama-3-turbo' => {
      provider: :together,
      api_name: 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
      name: 'Llama 3 Turbo',
      context_window: 128000,
      max_tokens: 2048,
      temperature: 0.7,
      input_cost_per_1M: 0,
      output_cost_per_1M: 0,
      description: 'Free high-performance recommendations'
    },
    'deepseek-chat' => {
      provider: :together,
      api_name: 'deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free',
      name: 'DeepSeek',
      context_window: 128000,
      max_tokens: 4096,
      temperature: 0.7,
      input_cost_per_1M: 0,
      output_cost_per_1M: 0,
      description: 'Strong recommendation capabilities'
    },
  }.freeze

  def self.default_model
    'gemini-2-flash'
  end

  def self.available_models
    MODELS
  end
end 
