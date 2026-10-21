class TestController < ApplicationController
  include Authentication
  skip_before_action :require_authentication

  def session
    resume_session  # <-- loads session into Current
    render json: { 
      session_id: cookies.signed[:_et_marketplace_session],
      current_user: current_user&.id
    }
  end
end