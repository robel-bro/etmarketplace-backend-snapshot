# app/policies/order_policy.rb

class OrderPolicy < ApplicationPolicy
  # ─── Listing ─────────────────────────────────────────
  def index?
    true  # controller scope controls what's shown
  end

  # ─── Viewing ─────────────────────────────────────────
  def show?
    user.admin? || record.user_id == user.id || seller_owner?
  end

  # ─── General updates (seller/admin) ─────────────────
  def update?
    user.admin? || seller_owner?
  end

  # ─── Seller status updates ──────────────────────────
  def update_status?
    user.admin? || seller_owner?
  end

  # ★ Seller accepts order – allow pending, pending_acceptance, paid
  def accept?
    seller_owner? && ['pending', 'pending_acceptance', 'paid'].include?(record.status)
  end

  # ★ Seller rejects order – allow pending, pending_acceptance, paid
  def reject?
    seller_owner? && ['pending', 'pending_acceptance', 'paid'].include?(record.status)
  end

  # ★ Seller marks processing
  def process?
    seller_owner? && record.accepted?
  end

  # ★ Seller marks shipped
  def ship?
    seller_owner? && record.processing?
  end

  # ★ Seller marks delivered (not used by seller controller anymore, but kept)
  def deliver?
    seller_owner? && record.shipped?
  end

  # ★ Complete (admin or seller after delivered)
  def complete?
    user.admin? || (seller_owner? && record.delivered?)
  end

  # ★ Cancel (admin, seller, or buyer)
  def cancel?
    user.admin? || seller_owner? || record.user_id == user.id
  end

  # ─── Toggle pickup readiness (consolidated delivery) ──
  def toggle_pickup_ready?
    user.admin? || seller_owner?
  end

  # ─── Invoice access ────────────────────────────────
  def invoice?
    show?
  end

  # ─── Public token generation ───────────────────────
  def generate_public_token?
    show?
  end

  # ─── Authenticated invoice data (JSON) ─────────────
  def invoice_data?
    show?
  end

  # ─── Authenticated invoice PDF data (base64 JSON) ──
  def invoice_pdf_data?
    show?
  end

  # ─── Admin COD reconciliation ──────────────────────
  def cod_reconcile?
    user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      elsif user.vendor.present?
        scope.where(vendor_id: user.vendor.id)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  private

  def seller_owner?
    user.vendor.present? && record.vendor_id.present? && user.vendor.id == record.vendor_id
  end
end