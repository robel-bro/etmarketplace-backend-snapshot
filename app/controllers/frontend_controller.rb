class FrontendController < ApplicationController
  skip_before_action :require_authentication

  def index
    # Ensure a fresh session cookie exists, so CSRF meta tag works
    session[:init] = true unless session[:init]
  end
end