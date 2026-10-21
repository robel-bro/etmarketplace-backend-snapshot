class DynamicDealAssignmentJob < ApplicationJob
  queue_as :default

  def perform
    Product.recompute_dynamic_deals!
  end
end