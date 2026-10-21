class VendorPolicy < ApplicationPolicy
  def show?
    user.admin? || user == record.user
  end

  def create?
    user.vendor.nil?
  end

  def update?
    user.admin? || user == record.user
  end
end