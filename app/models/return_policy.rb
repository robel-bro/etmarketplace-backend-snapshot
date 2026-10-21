class ReturnPolicy < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :return_window_days, numericality: { greater_than: 0 }
  validates :restocking_fee_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :return_shipping_responsibility, inclusion: { in: %w[buyer seller platform] }

  scope :active, -> { where(is_active: true) }

  # Returns the most specific policy for a given category
  def self.for_category(category_id)
    # Find a policy where applicable_categories includes this category, or fallback to global (empty array)
    policy = active.where("applicable_categories @> ?", [category_id].to_json).first
    policy || active.find_by(applicable_categories: [])  # global fallback
  end
end