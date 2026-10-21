class InvoiceGenerator
  def self.generate(order)
    {
      invoice_number: "INV-#{order.id}-#{Time.current.strftime('%Y%m%d')}",
      date: Time.current.iso8601,
      order_id: order.id,
      customer: {
        name: order.user.full_name,
        email: order.user.email_address
      },
      vendor: {
        business_name: order.vendor.business_name,
        tin: order.vendor.tin
      },
      items: order.line_items.map do |li|
        {
          product: li.product.title,
          quantity: li.quantity,
          unit_price: li.price.to_f,
          total: (li.price * li.quantity).to_f
        }
      end,
      subtotal: order.line_items.sum { |li| li.price * li.quantity }.to_f,
      shipping_cost: order.shipping_cost.to_f,
      total: order.total.to_f,
      payment_method: order.payment_method_enum,
      payment_status: order.payment_status,
      status: order.status
    }
  end
end