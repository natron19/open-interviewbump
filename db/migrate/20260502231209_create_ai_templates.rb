class CreateAiTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_templates, id: :uuid do |t|
      t.string  :name,                 null: false
      t.string  :description
      t.text    :system_prompt,        null: false
      t.text    :user_prompt_template, null: false
      t.string  :model,                default: "gemini-2.0-flash", null: false
      t.integer :max_output_tokens,    default: 2000,               null: false
      t.decimal :temperature,          default: 0.7, precision: 3, scale: 1
      t.text    :notes
      t.timestamps
    end

    add_index :ai_templates, :name, unique: true
  end
end
