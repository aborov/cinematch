class AiModelsConfig
  MODELS = {
    'gemini-2-flash' => {
      provider: :gemini,
      api_name: 'gemini-2.0-flash',
      name: 'Gemini 2.0 Flash',
      max_tokens: 8192,
      temperature: 1,
      cost_per_1k: 0.0001,
      description: 'Fast and efficient recommendations with Google AI'
    },
    'gemini-2-pro-exp' => {
      provider: :gemini,
      api_name: 'gemini-2.0-pro-exp-02-05',
      name: 'Gemini 2.0 Pro (Experimental)',
      max_tokens: 8192,
      temperature: 1,
      cost_per_1k: 0.0005,
      description: 'Advanced experimental model with enhanced capabilities'
    },
    'gpt-4o-mini' => {
      provider: :openai,
      api_name: 'gpt-4o-mini',
      name: 'GPT-4o Mini',
      max_tokens: 4000,
      temperature: 1,
      cost_per_1k: 0.001,
      description: 'Cost-effective, high-quality recommendations'
    },
    'gpt-3.5-turbo' => {
      provider: :openai,
      api_name: 'gpt-3.5-turbo',
      name: 'GPT-3.5 Turbo',
      max_tokens: 4000,
      temperature: 1,
      cost_per_1k: 0.002,
      description: 'Balanced performance and cost'
    },
    'claude-3-5-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-5-haiku-latest',
      name: 'Claude 3.5 Haiku',
      max_tokens: 8192,
      temperature: 1,
      cost_per_1k: 0.80,
      description: 'Intelligence at blazing speeds, optimized for quick recommendations'
    },
    'claude-3-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-haiku-20240307',
      name: 'Claude 3 Haiku',
      max_tokens: 4096,
      temperature: 1,
      cost_per_1k: 0.25,
      description: 'Quick and accurate targeted performance, ideal for instant recommendations'
    },
    'llama-3-turbo' => {
      provider: :together,
      api_name: 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
      name: 'Llama 3 Turbo',
      max_tokens: 4096,
      temperature: 1,
      cost_per_1k: 0,
      description: 'Free high-performance model from Meta'
    },
    'llama2' => {
      provider: :ollama,
      api_name: 'llama2',
      name: 'Llama 2',
      max_tokens: 4000,
      temperature: 1,
      cost_per_1k: 0,
      description: 'Free, locally hosted model'
    },
    'deepseek-chat' => {
      provider: :deepseek,
      api_name: 'deepseek-chat',
      name: 'DeepSeek',
      max_tokens: 2000,
      temperature: 1,
      cost_per_1k: 0.001,
      description: 'Open source model with strong recommendation capabilities'
    },
  }.freeze

  def self.default_model
    'gemini-2-flash'
  end

  def self.available_models
    MODELS
  end
end 
