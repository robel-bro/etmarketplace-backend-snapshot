class AddGeneratedSearchVectors < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      ALTER TABLE products
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english',
          coalesce(title, '') || ' ' ||
          coalesce(description, '') || ' ' ||
          coalesce(product_attributes::text, '')
        )
      ) STORED;
    SQL
    add_index :products, :search_vector, using: 'gin'

    execute <<-SQL
      ALTER TABLE packages
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english',
          coalesce(name, '') || ' ' ||
          coalesce(description, '')
        )
      ) STORED;
    SQL
    add_index :packages, :search_vector, using: 'gin'
  end

  def down
    remove_column :products, :search_vector
    remove_column :packages, :search_vector
  end
end
