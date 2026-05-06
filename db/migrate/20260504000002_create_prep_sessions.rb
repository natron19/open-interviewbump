class CreatePrepSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :prep_sessions, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :job_title, null: false
      t.string :company,   null: false
      t.text   :job_description
      t.string :status,        null: false, default: "pending"
      t.text   :error_message
      t.timestamps null: false
    end

    add_index :prep_sessions, :created_at
  end
end
