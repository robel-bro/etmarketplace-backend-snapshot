Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src  :self
  # Allow Google Fonts stylesheets
  policy.style_src   :self, :unsafe_inline, 'https://fonts.googleapis.com'
  policy.img_src     :self, :data, :https
  policy.connect_src :self
  # Allow Google Fonts font files
  policy.font_src    :self, :data, 'https://fonts.gstatic.com'
  policy.object_src  :none
  policy.frame_ancestors :none
  policy.form_action :self
  policy.base_uri    :self
end

# Set to false to enforce the policy (true = report only)
Rails.application.config.content_security_policy_report_only = false