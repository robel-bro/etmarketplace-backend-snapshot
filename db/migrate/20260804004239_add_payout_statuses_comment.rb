class AddPayoutStatusesComment < ActiveRecord::Migration[8.1]
  def change
    # The status column is already an integer.
    # Model supports: 0-pending, 1-paid, 2-cancelled, 3-processing, 4-failed, 5-rejected.
    # No structural change needed.
  end
end