class AddForwardingFieldsToCallSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :call_sessions, :caller_number, :string
    add_column :call_sessions, :conference_name, :string
    add_column :call_sessions, :initiator_call_sid, :string
    add_column :call_sessions, :connected_contact_id, :integer

    add_index :call_sessions, :initiator_call_sid, unique: true
    add_index :call_sessions, :connected_contact_id

    execute <<~SQL.squish
      UPDATE call_sessions
      SET conference_name = room_name
      WHERE conference_name IS NULL OR conference_name = ''
    SQL

    change_column_null :call_sessions, :conference_name, false
  end

  def down
    remove_index :call_sessions, :connected_contact_id
    remove_index :call_sessions, :initiator_call_sid

    remove_column :call_sessions, :connected_contact_id
    remove_column :call_sessions, :initiator_call_sid
    remove_column :call_sessions, :conference_name
    remove_column :call_sessions, :caller_number
  end
end
