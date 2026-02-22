class RemoveTierFromContacts < ActiveRecord::Migration[8.1]
  def change
    remove_index :contacts, name: "index_contacts_on_user_id_and_tier_and_priority_and_active", if_exists: true
    remove_check_constraint :contacts, name: "contacts_tier_range", if_exists: true
    remove_column :contacts, :tier, :integer

    add_index :contacts, [ :user_id, :priority, :active ], if_not_exists: true
  end
end
