class Current < ActiveSupport::CurrentAttributes
  attribute :session, :ip_address, :user_agent

  def user
    session&.user
  end
end