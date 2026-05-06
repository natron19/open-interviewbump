class AiTemplate < ApplicationRecord
  validates :name,                 presence: true, uniqueness: true
  validates :system_prompt,        presence: true
  validates :user_prompt_template, presence: true
  validates :model,                presence: true
  validates :max_output_tokens,    presence: true, numericality: { greater_than: 0 }
  validates :temperature,          numericality: { greater_than_or_equal_to: 0.0,
                                                   less_than_or_equal_to: 2.0 }

  def variable_names
    user_prompt_template.scan(/\{\{(\w+)\}\}/).flatten.uniq
  end

  def interpolate(variables = {})
    result = user_prompt_template.dup
    variables.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
    end
    result
  end
end
