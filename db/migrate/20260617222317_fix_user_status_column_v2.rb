class FixUserStatusColumnV2 < ActiveRecord::Migration[8.1]
  def up
    # 1. Remove the old default (string 'active')
    change_column_default :users, :status, nil

    # 2. Map existing string values to integer strings, then cast
    execute <<-SQL
      UPDATE users SET status = '0' WHERE status = 'active';
      UPDATE users SET status = '1' WHERE status = 'inactive';
      UPDATE users SET status = '2' WHERE status = 'banned';
      UPDATE users SET status = '0' WHERE status IS NULL OR status NOT IN ('0','1','2');
    SQL

    # 3. Change column type to integer with a new default
    change_column :users, :status, :integer, using: 'status::integer', default: 0, null: false
  end

  def down
    change_column :users, :status, :string, default: 'active'
    execute <<-SQL
      UPDATE users SET status = 'active' WHERE status = '0';
      UPDATE users SET status = 'inactive' WHERE status = '1';
      UPDATE users SET status = 'banned' WHERE status = '2';
    SQL
  end
end
