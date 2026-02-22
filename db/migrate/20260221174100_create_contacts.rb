class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :phone_e164, null: false
      t.string :relationship

      t.integer :tier, null: false
      t.integer :priority, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.integer :consent_status, null: false, default: 0
      t.datetime :consent_confirmed_at
      t.time :preferred_hours_start
      t.time :preferred_hours_end
      t.string :timezone

      t.datetime :last_contacted_at
      t.datetime :last_responded_at
      t.integer :response_count, null: false, default: 0
      t.integer :miss_count, null: false, default: 0
      t.integer :avg_answer_seconds

      t.timestamps
    end

    add_index :contacts, [ :user_id, :phone_e164 ], unique: true
    add_index :contacts, [ :user_id, :tier, :priority, :active ]

    add_check_constraint :contacts, "tier IN (1, 2, 3)", name: "contacts_tier_range"
    add_check_constraint :contacts, "priority >= 0", name: "contacts_priority_non_negative"
    add_check_constraint :contacts, "response_count >= 0", name: "contacts_response_count_non_negative"
    add_check_constraint :contacts, "miss_count >= 0", name: "contacts_miss_count_non_negative"
    add_check_constraint :contacts, "avg_answer_seconds IS NULL OR avg_answer_seconds >= 0", name: "contacts_avg_answer_seconds_non_negative"
  end
end
