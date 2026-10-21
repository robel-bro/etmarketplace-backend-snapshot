class BulkOrderItem < ApplicationRecord
  belongs_to :bulk_order
  belongs_to :product
end
