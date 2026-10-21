# app/jobs/update_product_stats_job.rb
class UpdateProductStatsJob < ApplicationJob
  queue_as :default

  # Increment views for a single product (called from product detail controller)
  def perform(product_id)
    product = Product.find_by(id: product_id)
    return unless product

    product.increment!(:views_count)
  end

  # Master method – called by the cron job every 2 hours
  def self.perform_full_update
    # 1. Update sold_count from delivered orders
    Product.find_each do |product|
      sold = product.line_items.joins(:order).where(orders: { status: :delivered }).sum(:quantity)
      product.update(sold_count: sold) if product.sold_count != sold
    end

    # 2. Run the fully automated promotions engine
    Product.recompute_dynamic_deals!

    Rails.logger.info "[UpdateProductStatsJob] Full stats + promotions update completed at #{Time.current}"
  end
end