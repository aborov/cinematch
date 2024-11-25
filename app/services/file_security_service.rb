class FileSecurityService
  ALLOWED_CONTENT_TYPES = ['image/jpeg', 'image/png', 'application/pdf'].freeze
  MAX_FILE_SIZE = 5.megabytes
  ALLOWED_EXTENSIONS = %w[.jpg .jpeg .png .pdf].freeze

  class FileSecurityError < StandardError; end

  def self.validate_and_sanitize(attachment)
    new(attachment).validate_and_sanitize
  end

  def initialize(attachment)
    @attachment = attachment
  end

  def validate_and_sanitize
    validate_file_size
    validate_content_type
    validate_file_extension
    scan_for_viruses if Rails.env.production?
    sanitize_filename

    @attachment
  end

  private

  def validate_file_size
    return unless @attachment.size > MAX_FILE_SIZE

    raise FileSecurityError, 'File size exceeds maximum allowed size'
  end

  def validate_content_type
    return if @attachment.content_type.in?(ALLOWED_CONTENT_TYPES)

    raise FileSecurityError, 'Invalid file type'
  end

  def validate_file_extension
    extension = File.extname(@attachment.original_filename).downcase
    return if extension.in?(ALLOWED_EXTENSIONS)

    raise FileSecurityError, 'Invalid file extension'
  end

  def scan_for_viruses
    return unless Rails.env.production? && ENV['CLAMAV_ENABLED'] == 'true'
    
    scan_result = CLAM_SCANNER.scan_file(@attachment.tempfile.path)
    raise FileSecurityError, 'File failed security scan' unless scan_result.clean?
  rescue StandardError => e
    Rails.logger.error "Virus scan error: #{e.message}"
    raise FileSecurityError, 'File security scan failed'
  end

  def sanitize_filename
    sanitized = @attachment.original_filename.encode('UTF-8', invalid: :replace, undef: :replace)
    sanitized = sanitized.strip
    sanitized = sanitized.gsub(/[^0-9A-Za-z.\-]/, '_')
    sanitized = sanitized.gsub(/__+/, '_')
    sanitized = sanitized.gsub(/^\.+|\.+$/, '')
    sanitized = "unnamed" if sanitized.blank?
    
    @attachment.original_filename = sanitized
  end
end 
