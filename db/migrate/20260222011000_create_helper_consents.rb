class CreateHelperConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :helper_consents do |t|
      t.string :consent_hash, null: false
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :helper_consents, :consent_hash, unique: true
    add_index :helper_consents, :status
  end
end
