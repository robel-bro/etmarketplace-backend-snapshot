class AddHeldToPayouts < ActiveRecord::Migration[8.1]
  def change
    add_column :payouts, :held, :boolean, default: false
  end
end
