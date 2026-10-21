class InvoicesController < ApplicationController
  def show
    @order = Order.find(params[:id])
    # Optional: set company info – adjust to your actual settings
    @company_name = "Your Company Name"
    @company_email = "hello@yourcompany.com"

    respond_to do |format|
      format.pdf do
        render pdf: "invoice_#{@order.id}",
               template: "invoices/show",
               layout: "pdf",
               page_size: "A4",
               margin: { top: 10, bottom: 10, left: 10, right: 10 },
               encoding: "UTF-8",
               no_outline: true,
               print_media_type: true,
               disable_smart_shrinking: true
      end
    end
  end
end