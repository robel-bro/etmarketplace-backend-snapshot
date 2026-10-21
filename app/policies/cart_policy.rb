class CartPolicy < ApplicationPolicy
  def show?
    user.present? && (record.user_id == user.id || user.admin?)
  end

  def add_item?
    show?
  end

  def add_items?
    show?
  end

  def update_item?
    show?
  end

  def remove_item?
    show?
  end

  def merge?
    show?
  end
end