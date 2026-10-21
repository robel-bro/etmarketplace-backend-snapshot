class Admin::AnnouncementsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_announcement, only: [:update, :destroy]

  def index
    @announcements = AdminAnnouncement.all.order(created_at: :desc)
    render json: @announcements.map { |a| announcement_json(a) }
  end

  def create
    @announcement = AdminAnnouncement.new(announcement_params.except(:image))
    if @announcement.save
      if params[:announcement][:image].present?
        @announcement.image.attach(params[:announcement][:image])
      end
      # Use the full qualified class name – the model is AdminAuditLog
      if defined?(::AdminAuditLog) && ::AdminAuditLog.respond_to?(:log)
        ::AdminAuditLog.log(current_user, 'announcement_created', @announcement, { title: @announcement.title })
      end
      render json: announcement_json(@announcement), status: :created
    else
      render json: { errors: @announcement.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_title = @announcement.title
    if @announcement.update(announcement_params.except(:image))
      if params[:announcement][:image].present?
        @announcement.image.purge if @announcement.image.attached?
        @announcement.image.attach(params[:announcement][:image])
      end
      if defined?(::AdminAuditLog) && ::AdminAuditLog.respond_to?(:log)
        ::AdminAuditLog.log(current_user, 'announcement_updated', @announcement, { old_title: old_title, new_title: @announcement.title })
      end
      render json: announcement_json(@announcement)
    else
      render json: { errors: @announcement.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    info = { id: @announcement.id, title: @announcement.title }
    @announcement.destroy
    if defined?(::AdminAuditLog) && ::AdminAuditLog.respond_to?(:log)
      ::AdminAuditLog.log(current_user, 'announcement_deleted', nil, info)
    end
    head :no_content
  end

  private

  def set_announcement
    @announcement = AdminAnnouncement.find(params[:id])
  end

  def announcement_params
    params.require(:announcement).permit(:title, :content, :announcement_type, :image, :active, :start_date, :end_date, :link)
  end

  def announcement_json(announcement)
    {
      id: announcement.id,
      title: announcement.title,
      content: announcement.content,
      announcement_type: announcement.announcement_type,
      image_url: announcement.image.attached? ? url_for(announcement.image) : nil,
      link: announcement.link,
      active: announcement.active,
      start_date: announcement.start_date,
      end_date: announcement.end_date,
      created_at: announcement.created_at
    }
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'announcements' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('announcements')
    head :forbidden
    false
  end
end