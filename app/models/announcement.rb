class Announcement < ApplicationRecord
  validates :title, :content, presence: true
  scope :active, -> { where(active: true) }

  # ── Lifecycle callback for automated notification ──
  after_commit :broadcast_announcement, on: :create

  private

  def broadcast_announcement
    # Only broadcast if the announcement is active (otherwise it's a draft)
    return unless active?

    PromotionBroadcastJob.perform_later(:announcement, {
      title: title,
      body: content
    })
  end
end