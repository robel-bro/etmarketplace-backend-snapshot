class PromotionalSectionProduct < ApplicationRecord
  belongs_to :promotional_section
  belongs_to :product
end
