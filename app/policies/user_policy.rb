class UserPolicy < ApplicationPolicy
  # Only admins can list users
  def index?
    user.admin?
  end

  # Users can view their own profile; admins can view any
  def show?
    user.admin? || record == user
  end

  # Only admins can update roles or verify users
  def update?
    user.admin?
  end

  # Only admins can delete users
  def destroy?
    user.admin?
  end
end