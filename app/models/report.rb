class Report < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :reason, presence: true
  validates :status, inclusion: { in: %w[pending reviewed resolved] }
end