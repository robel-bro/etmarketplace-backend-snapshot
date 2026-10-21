class CreateMembershipPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_plans do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, default: 0
      t.integer :duration_days
      t.decimal :commission_rate, precision: 5, scale: 2
      t.string :badge_text
      t.boolean :priority_support, default: false
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
