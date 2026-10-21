class ProductPolicy < ApplicationPolicy
  def index?
    true  # anyone can list products
  end

  def show?
    true  # anyone can view a product
  end

  def create?
    user.seller? && user.vendor.present? && user.vendor.approved?
  end

  def update?
    record.vendor.user == user || user.admin?
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      if user&.admin?
        scope.all
      elsif user&.seller?
        scope.where(vendor: user.vendor)
      else
        scope.where(status: :active)
      end
    end
  end
end