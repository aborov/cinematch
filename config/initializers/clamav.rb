if Rails.env.production?
  require 'clamav/client'
  ClamAV.configure do |config|
    config.location = '/usr/local/bin/clamscan'
    config.error_clamscan_missing = true
    config.error_file_missing = true
    config.error_file_virus = true
  end
end

# Add mock ClamAV client for development
unless Rails.env.production?
  module ClamAV
    class MockScanner
      def self.scan_file(_path)
        OpenStruct.new(clean?: true)
      end
    end

    def self.instance
      MockScanner
    end
  end
end 
