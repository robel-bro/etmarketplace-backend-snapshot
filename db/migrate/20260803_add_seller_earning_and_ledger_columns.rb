class AddSellerEarningAndLedgerColumns < ActiveRecord::Migration[8.1]
  def change
    # --- Orders: seller_earning (immutable) ---
    unless column_exists?(:orders, :seller_earning)
      add_column :orders, :seller_earning, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    end

    # --- Financial Ledgers: double-entry columns ---
    unless column_exists?(:financial_ledgers, :debit_account)
      add_column :financial_ledgers, :debit_account, :string
    end
    unless column_exists?(:financial_ledgers, :credit_account)
      add_column :financial_ledgers, :credit_account, :string
    end

    # Add index for faster reconciliation
    add_index :financial_ledgers, :debit_account unless index_exists?(:financial_ledgers, :debit_account)
    add_index :financial_ledgers, :credit_account unless index_exists?(:financial_ledgers, :credit_account)

    # Clean up duplicate migration conflict (if AddMissingFinancialColumnsToOrders ran, it's fine; if not, prevent future error)
    # No direct action needed here; we'll handle in schema.rb by ensuring columns exist.
  end
end