class UserMailer < ApplicationMailer
  def price_alert(user, product, target_price)
    @user = user
    @product = product
    @target_price = target_price
    mail(to: user.email_address, subject: "Price Drop Alert: #{product.title}")
  end
end