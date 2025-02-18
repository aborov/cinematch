class AiModelsConfig
  MODELS = {
    'gpt-4o-mini' => {
      provider: :openai,
      api_name: 'gpt-4o-mini',
      name: 'GPT-4o Mini',
      max_tokens: 4000,
      temperature: 0.7,
      cost_per_1k: 0.001,
      description: 'Cost-effective, high-quality recommendations'
    },
    'gpt-3.5-turbo' => {
      provider: :openai,
      api_name: 'gpt-3.5-turbo',
      name: 'GPT-3.5 Turbo',
      max_tokens: 4000,
      temperature: 0.7,
      cost_per_1k: 0.002,
      description: 'Balanced performance and cost'
    },
    'claude-3-5-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-5-haiku-latest',
      name: 'Claude 3.5 Haiku',
      max_tokens: 8192,
      temperature: 0.7,
      cost_per_1k: 0.80,
      description: 'Intelligence at blazing speeds, optimized for quick recommendations'
    },
    'claude-3-haiku' => {
      provider: :anthropic,
      api_name: 'claude-3-haiku-20240307',
      name: 'Claude 3 Haiku',
      max_tokens: 4096,
      temperature: 0.7,
      cost_per_1k: 0.25,
      description: 'Quick and accurate targeted performance, ideal for instant recommendations'
    },
    'llama2' => {
      provider: :ollama,
      api_name: 'llama2',
      name: 'Llama 2',
      max_tokens: 4000,
      temperature: 0.7,
      cost_per_1k: 0,
      description: 'Free, locally hosted model'
    }
  }.freeze

  def self.default_model
    'gpt-4o-mini'
  end

  def self.available_models
    MODELS
  end
end 
