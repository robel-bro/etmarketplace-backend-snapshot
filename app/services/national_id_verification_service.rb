class NationalIdVerificationService
  def self.verify(national_id, full_name = nil)
    if ENV['NID_VERIFICATION_MODE'] == 'real'
      # Real integration with Ethiopian national ID system
      # This would be a third‑party API (e.g., through a government portal)
      raise NotImplementedError, "Real national ID verification not implemented yet"
    else
      # Mock: accept any ID with at least 8 digits
      if national_id.to_s.match?(/^\d{8,}$/)
        { success: true, verified: true, message: "ID is valid" }
      else
        { success: false, verified: false, message: "Invalid national ID format (must be at least 8 digits)" }
      end
    end
  end
end