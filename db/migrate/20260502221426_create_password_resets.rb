class CreatePasswordResets < ActiveRecord::Migration[8.1]
  def change
    create_table :password_resets, id: :uuid do |t|
      t.references :user,       null: false, foreign_key: true, type: :uuid
      t.string     :token,      null: false
      t.datetime   :expires_at, null: false
      t.datetime   :used_at
      t.timestamps
    end

    add_index :password_resets, :token, unique: true
  end
end
