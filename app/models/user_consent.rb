class UserConsent < ApplicationRecord
  belongs_to :user

  validates :agreement_type, presence: true
  validates :agreement_version, presence: true
  validates :accepted_at, presence: true
  validates :agreement_type, uniqueness: { scope: :user_id }
end