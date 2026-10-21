# app/mailers/notification_mailer.rb

class NotificationMailer < ApplicationMailer
  default from: ENV.fetch('MAIL_FROM', 'noreply@etmarketplace.com')

  def notify
    @user  = params[:user]
    @title = params[:title] || 'ET Marketplace Notification'
    @body  = params[:body] || ''
    @type  = params[:type] || 'general'

    # Safety: if user or email is missing, return an empty mail object
    return if @user.nil? || @user.email.blank?

    mail(
      to: @user.email,
      subject: "ET Marketplace – #{@title}"
    )
  end
end