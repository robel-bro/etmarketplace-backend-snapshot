class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :reason, null: false
      t.text :comment
      t.string :status, default: 'pending'   # pending, reviewed, resolved
      t.timestamps
    end
  end
end
