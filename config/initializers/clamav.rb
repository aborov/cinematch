if Rails.env.production? && ENV['CLAMAV_ENABLED'] == 'true'
  require 'clamav/client'
  
  begin
    CLAM_SCANNER = ClamAV::Client.new(
      host: 'localhost',
      port: 3310,
      timeout: 30
    )
  rescue StandardError => e
    Rails.logger.error("Failed to initialize ClamAV: #{e.message}")
    CLAM_SCANNER = OpenStruct.new(
      scan_file: ->(_path) { OpenStruct.new(clean?: true) }
    )
  end
else
  # Mock scanner that matches the production interface
  CLAM_SCANNER = OpenStruct.new(
    scan_file: ->(_path) { OpenStruct.new(clean?: true) }
  )
end 
