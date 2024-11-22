if Rails.env.production?
  require 'clamav/client'
  
  CLAM_SCANNER = ClamAV::Client.new(
    location: '/usr/local/bin/clamscan',
    raise_errors: true,
    options: {
      database: '/var/lib/clamav',
      stdout: true,
      recursive: true,
      quiet: true
    }
  )
else
  # Mock scanner that matches the production interface
  CLAM_SCANNER = OpenStruct.new(
    scan_file: ->(_path) { OpenStruct.new(clean?: true) }
  )
end 
