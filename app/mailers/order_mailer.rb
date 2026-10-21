class OrderMailer < ApplicationMailer
  def order_confirmation(order)
    @order = order
    @user = order.user
    @line_items = order.line_items.includes(:product)
    @total = order.total
    @shipping_cost = order.shipping_cost
    @grand_total = order.total + order.shipping_cost

    mail(
      to: @user.email,
      subject: "Order Confirmation ##{order.id}"
    )
  end
end