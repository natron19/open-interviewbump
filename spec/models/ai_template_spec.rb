require "rails_helper"

RSpec.describe AiTemplate, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:ai_template)).to be_valid
    end

    it "requires name" do
      expect(build(:ai_template, name: nil)).not_to be_valid
    end

    it "requires name to be unique" do
      create(:ai_template, name: "my_template")
      expect(build(:ai_template, name: "my_template")).not_to be_valid
    end

    it "requires system_prompt" do
      expect(build(:ai_template, system_prompt: nil)).not_to be_valid
    end

    it "requires user_prompt_template" do
      expect(build(:ai_template, user_prompt_template: nil)).not_to be_valid
    end

    it "requires model" do
      expect(build(:ai_template, model: nil)).not_to be_valid
    end

    it "requires temperature to be between 0.0 and 2.0" do
      expect(build(:ai_template, temperature: -0.1)).not_to be_valid
      expect(build(:ai_template, temperature: 2.1)).not_to be_valid
      expect(build(:ai_template, temperature: 0.0)).to be_valid
      expect(build(:ai_template, temperature: 2.0)).to be_valid
    end
  end

  describe "#variable_names" do
    it "returns variable names from {{...}} placeholders" do
      template = build(:ai_template, user_prompt_template: "Hello {{name}}, topic is {{topic}}.")
      expect(template.variable_names).to contain_exactly("name", "topic")
    end

    it "returns empty array when no placeholders" do
      template = build(:ai_template, user_prompt_template: "No variables here.")
      expect(template.variable_names).to eq([])
    end

    it "deduplicates repeated placeholders" do
      template = build(:ai_template, user_prompt_template: "{{name}} and {{name}} again.")
      expect(template.variable_names).to eq(["name"])
    end
  end

  describe "#interpolate" do
    it "substitutes all variables" do
      template = build(:ai_template, user_prompt_template: "Hello {{name}}, you are {{age}}.")
      result = template.interpolate(name: "Alice", age: "30")
      expect(result).to eq("Hello Alice, you are 30.")
    end

    it "leaves unmatched placeholders as-is" do
      template = build(:ai_template, user_prompt_template: "Hello {{name}} and {{other}}.")
      result = template.interpolate(name: "Alice")
      expect(result).to eq("Hello Alice and {{other}}.")
    end
  end
end
