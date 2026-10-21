# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user || reject_unauthorized_connection
    end

    private

    def find_verified_user
      # 1. Try JWT from query string (mobile & frontend partners)
      token = request.params[:token]
      if token.present?
        payload = JsonWebToken.decode(token)
        return User.find_by(id: payload['user_id'])
      end

      # 2. Fall back to signed cookie session (traditional browser clients)
      session = Session.find_by(id: cookies.signed[:session_id])
      return session.user if session

      nil
    rescue
      nil
    end
  end
end