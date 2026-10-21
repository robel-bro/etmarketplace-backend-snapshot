class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Helper to get a setting value (JSON parsed automatically)
  def self.get(key, default = nil)
    setting = find_by(key: key)
    return default unless setting

    begin
      JSON.parse(setting.value)
    rescue
      setting.value
    end
  end

  # Helper to set a setting value
  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value.is_a?(String) ? value : value.to_json
    setting.save!
  end
end