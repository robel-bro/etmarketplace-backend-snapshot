class Api::V1::MembershipPlansController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    plans = MembershipPlan.where(active: true)
    render json: plans.map { |p| plan_json(p) }
  end

  private

  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      price: plan.price.to_f,
      yearly_price: plan.yearly_price&.to_f,         # ★ new – can be null
      duration_days: plan.duration_days,
      commission_rate: plan.commission_rate.to_f,
      badge_text: plan.badge_text,
      priority_support: plan.priority_support,
      active: plan.active,
      features: plan.features || [],
      featured_included: plan.featured_included,
      featured_duration_days: plan.featured_duration_days,
      sponsored_product_limit: plan.sponsored_product_limit,
      analytics_access: plan.analytics_access
    }
  end
end