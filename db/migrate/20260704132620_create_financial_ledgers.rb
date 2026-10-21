class CreateFinancialLedgers < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_ledgers do |t|
      t.string :transaction_type
      t.decimal :amount, precision: 10, scale: 2
      t.string :description
      t.references :ledgerable, polymorphic: true, null: false

      t.timestamps
    end
  end
end
