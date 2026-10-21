class Api::BuyerVerificationController < ApplicationController
  before_action :require_authentication

  def create
    national_id = params[:user][:national_id]
    verification = NationalIdVerificationService.verify(national_id)

    if verification[:success]
      if current_user.update(verification_params)
        render json: { message: "Verification successful", user: current_user }, status: :ok
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { error: verification[:message] }, status: :unprocessable_entity
    end
  end

  private

  def verification_params
    params.require(:user).permit(:phone, :national_id)
  end
end