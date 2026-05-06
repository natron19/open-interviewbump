class CreateLlmRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_requests, id: :uuid do |t|
      t.references :user,         null: false, foreign_key: true, type: :uuid
      t.references :ai_template,  null: true,  foreign_key: true, type: :uuid
      t.string  :template_name
      t.string  :status,          null: false, default: "pending"
      t.integer :prompt_token_count
      t.integer :response_token_count
      t.integer :duration_ms
      t.decimal :cost_estimate_cents, precision: 10, scale: 4
      t.text    :error_message
      t.timestamps
    end

    add_index :llm_requests, :created_at
    add_index :llm_requests, :status
  end
end
