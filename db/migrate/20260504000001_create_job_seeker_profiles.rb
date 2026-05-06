class CreateJobSeekerProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :job_seeker_profiles, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :background_summary
      t.timestamps null: false
    end
  end
end
