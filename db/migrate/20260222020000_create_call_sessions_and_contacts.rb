class CreateCallSessionsAndContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :call_sessions do |t|
      t.string :room_name, null: false
      t.string :caller_name, null: false
      t.string :status, null: false, default: "calling"

      t.timestamps
    end

    add_index :call_sessions, :status
    add_index :call_sessions, :created_at

    create_table :call_session_contacts do |t|
      t.references :call_session, null: false, foreign_key: true
      t.string :phone_number, null: false
      t.string :call_sid
      t.string :status, null: false, default: "queued"
      t.string :error_message
      t.datetime :last_event_at

      t.timestamps
    end

    add_index :call_session_contacts, :call_sid, unique: true
    add_index :call_session_contacts, %i[call_session_id phone_number], unique: true
    add_index :call_session_contacts, :status
    add_index :call_session_contacts, :updated_at
  end
end
