FactoryBot.define do
  factory :ai_template do
    sequence(:name)  { |n| "template_v#{n}" }
    description          { "A test template" }
    system_prompt        { "You are a helpful assistant." }
    user_prompt_template { "Say hello to {{name}}." }
    model                { "gemini-2.5-flash" }
    max_output_tokens    { 500 }
    temperature          { 0.7 }
  end
end
