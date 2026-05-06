class CreatePrepGuides < ActiveRecord::Migration[8.1]
  def change
    create_table :prep_guides, id: :uuid do |t|
      t.references :prep_session, null: false, foreign_key: true, type: :uuid
      t.text :likely_questions
      t.text :star_outlines
      t.text :questions_to_ask
      t.text :watch_out
      t.text :company_signals
      t.text :sources
      t.text :agent_trace
      t.text :gemini_raw
      t.timestamps null: false
    end
  end
end
