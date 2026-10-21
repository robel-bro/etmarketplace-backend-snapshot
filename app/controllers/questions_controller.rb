class QuestionsController < ApplicationController
  before_action :require_authentication, only: [:create]
  allow_unauthenticated_access only: [:index]

  def index
    questions = Question.where(product_id: params[:product_id]).includes(:answers)
    render json: questions.as_json(include: { answers: { methods: [:user_name] } })
  end

  def create
    question = current_user.questions.new(question_params)
    if question.save
      render json: question, status: :created
    else
      render json: { errors: question.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def question_params
    params.require(:question).permit(:product_id, :question)
  end
end