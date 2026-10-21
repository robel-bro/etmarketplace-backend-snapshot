class AddRefreshTokenDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :refresh_token_digest, :string
  end
end
