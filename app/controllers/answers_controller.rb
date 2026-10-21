class AnswersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_seller

  def create
    answer = Answer.new(answer_params)
    if answer.save
      render json: answer, status: :created
    else
      render json: { errors: answer.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def answer_params
    params.require(:answer).permit(:question_id, :answer)
  end

  def authorize_seller
    question = Question.find(params[:answer][:question_id])
    product = question.product
    head :forbidden unless current_user.seller? && current_user.vendor.products.exists?(id: product.id)
  end
end