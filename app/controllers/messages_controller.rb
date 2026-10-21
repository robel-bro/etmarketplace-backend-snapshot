class MessagesController < ApplicationController
  before_action :require_authentication

  def index
    # Get conversations with another user (if ?with=user_id)
    if params[:with]
      other_user = User.find(params[:with])
      messages = Message.where(
        "(sender_id = :current AND receiver_id = :other) OR (sender_id = :other AND receiver_id = :current)",
        current: current_user.id, other: other_user.id
      ).order(:created_at)
      render json: messages
    else
      # List unique conversation partners
      # This is simplified – in real app you'd have a Conversations model.
      conversation_ids = Message.where("sender_id = ? OR receiver_id = ?", current_user.id, current_user.id)
                                 .pluck(:sender_id, :receiver_id).flatten.uniq - [current_user.id]
      users = User.where(id: conversation_ids)
      render json: users
    end
  end

  def create
    @message = current_user.sent_messages.new(message_params)
    if @message.save
      render json: @message, status: :created
    else
      render json: { errors: @message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:message).permit(:receiver_id, :content)
  end
end