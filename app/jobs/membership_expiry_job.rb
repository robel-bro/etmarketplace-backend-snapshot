class MembershipExpiryJob < ApplicationJob
  queue_as :default

  def perform
    Vendor.where.not(membership_expires_at: nil)
          .where('membership_expires_at < ?', Time.current)
          .find_each do |vendor|
      vendor.remove_membership!
      Rails.logger.info "Membership expired for vendor #{vendor.id} (#{vendor.business_name})"
    end

    # Also clean up expired featured vendors (those without a plan)
    Vendor.where(featured: true)
          .where.not(featured_until: nil)
          .where('featured_until < ?', Time.current)
          .update_all(featured: false, featured_until: nil)
  end
end