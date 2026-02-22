class AddAutoCancelOnAcceptToCallSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :call_sessions, :auto_cancel_on_accept, :boolean, default: true, null: false
  end
end
