class AddPayoutFields < ActiveRecord::Migration[8.1]
  def change
    # ── Vendors: payout method and telebirr wallet ──
    unless column_exists?(:vendors, :payout_method)
      add_column :vendors, :payout_method, :integer, default: 0   # 0 = telebirr, 1 = bank
    end
    unless column_exists?(:vendors, :telebirr_account)
      add_column :vendors, :telebirr_account, :string   # phone number for Telebirr wallet
    end

    # ── Vendors: bank details (already may exist as bank_account_number, bank_name? – we ensure they are there) ──
    unless column_exists?(:vendors, :bank_account_number)
      add_column :vendors, :bank_account_number, :string
    end
    unless column_exists?(:vendors, :bank_name)
      add_column :vendors, :bank_name, :string
    end

    # ── Payouts: payout method snapshot, recipient details, gateway reference, processed_at ──
    unless column_exists?(:payouts, :payout_method)
      add_column :payouts, :payout_method, :string
    end
    unless column_exists?(:payouts, :recipient_details)
      add_column :payouts, :recipient_details, :jsonb, default: {}
    end
    unless column_exists?(:payouts, :gateway_reference)
      add_column :payouts, :gateway_reference, :string
    end
    unless column_exists?(:payouts, :processed_at)
      add_column :payouts, :processed_at, :datetime
    end
    unless column_exists?(:payouts, :held)
      add_column :payouts, :held, :boolean, default: false
    end

    # ── FinancialLedgers: double‑entry columns (if migration from Round 1 didn't run) ──
    unless column_exists?(:financial_ledgers, :debit_account)
      add_column :financial_ledgers, :debit_account, :string
    end
    unless column_exists?(:financial_ledgers, :credit_account)
      add_column :financial_ledgers, :credit_account, :string
    end
    unless index_exists?(:financial_ledgers, :debit_account)
      add_index :financial_ledgers, :debit_account
    end
    unless index_exists?(:financial_ledgers, :credit_account)
      add_index :financial_ledgers, :credit_account
    end

    # ── Orders: seller_earning column (if missing) ──
    unless column_exists?(:orders, :seller_earning)
      add_column :orders, :seller_earning, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    end
  end
end