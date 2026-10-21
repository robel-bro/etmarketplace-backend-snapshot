class VendorSubscriptionController < ApplicationController
  before_action :require_authentication
  before_action :require_seller!
  before_action :set_plan

  # POST /vendor_subscription
  def create
    vendor = current_user.vendor
    return render json: { error: 'Vendor not found' }, status: :not_found unless vendor

    if vendor.membership_plan&.active?
      return render json: { error: 'You already have an active plan' }, status: :unprocessable_entity
    end

    billing_cycle = params[:billing_cycle] || 'monthly'

    amount = case billing_cycle
             when 'yearly'
               @plan.yearly_price.presence || (@plan.price * 12 * 0.8).round(2)
             else
               @plan.price
             end

    idempotency_key = "membership_#{vendor.id}_#{billing_cycle}_#{Time.current.to_i}"

    result = PaymentService.process_membership(
      vendor: vendor,
      plan: @plan,
      amount: amount,
      idempotency_key: idempotency_key,
      payment_method: params[:payment_method]
    )

    if result[:success]
      render json: {
        redirect_url: result[:redirect_url],
        message: "Redirecting to payment..."
      }, status: :ok
    else
      render json: { error: result[:error] || 'Payment failed' }, status: :unprocessable_entity
    end
  end

  # DELETE /vendor_subscription
  def destroy
    vendor = current_user.vendor
    vendor.remove_membership!
    render json: { message: 'Subscription cancelled' }
  end

  private

  def set_plan
    @plan = MembershipPlan.active.find_by(id: params[:membership_plan_id])
    render json: { error: 'Plan not found' }, status: :not_found unless @plan
  end
end