class PackagePolicy < ApplicationPolicy
  # Only the vendor who owns the package can edit/destroy it
  def update?
    record.vendor.user == user
  end

  def destroy?
    record.vendor.user == user
  end

  # Any active seller can create
  def create?
    user.seller? && user.vendor.present?
  end

  class Scope < Scope
    def resolve
      # By default, only show packages belonging to active vendors
      scope.joins(vendor: :user).where(users: { status: :active })
    end
  end
end