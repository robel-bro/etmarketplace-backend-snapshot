# app/controllers/legal_pages_controller.rb
class LegalPagesController < ApplicationController
  skip_before_action :require_authentication

  # GET /legal/:key
  def show
    page = LegalPage.published.find_by!(key: params[:key])
    render json: {
      key: page.key,
      title: page.title,
      body: page.body,
      version: page.version,
      updated_at: page.updated_at
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Page not found" }, status: :not_found
  end
end