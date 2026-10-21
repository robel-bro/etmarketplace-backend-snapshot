# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Default: deny all
  def index?   ; false ; end
  def show?    ; false ; end
  def create?  ; false ; end
  def new?     ; create? ; end
  def update?  ; false ; end
  def edit?    ; update? ; end
  def destroy? ; false ; end

  # Scope that by default returns nothing – subclasses must override
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end
  end

  private

  # --- Role helpers ---
  def admin?
    user&.admin?
  end

  def seller?
    user&.seller?
  end

  def buyer?
    user&.buyer?
  end

  def active?
    user && !user.locked? && !user.deactivated?
  end

  # --- Ownership helper for sellers ---
  def owns_record?
    return false unless record.respond_to?(:seller) || record.respond_to?(:vendor)
    # Typical association: record belongs_to :product -> product.seller or record has seller_id
    seller_id = if record.respond_to?(:seller_id)
                  record.seller_id
                elsif record.respond_to?(:product) && record.product.respond_to?(:seller_id)
                  record.product.seller_id
                end
    seller_id && user.vendor&.id == seller_id
  end
end