class CreateReturnRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :return_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.string :reason
      t.text :details
      t.integer :status

      t.timestamps
    end
  end
end
