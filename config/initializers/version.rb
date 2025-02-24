module VersionInfo
  def self.get_version
    # Try to get version from git tags
    git_version = `git describe --tags --abbrev=0 2>/dev/null`.chomp
    return git_version unless git_version.empty?

    # Fallback to git commit count + hash
    git_count = `git rev-list --count HEAD 2>/dev/null`.chomp
    git_hash = `git rev-parse --short HEAD 2>/dev/null`.chomp
    
    if git_count.present? && git_hash.present?
      "0.#{git_count}.#{git_hash}"
    else
      '1.0.0'
    end
  end

  def self.get_changelog
    # Get all tags sorted by date
    tags = `git tag --sort=-creatordate`.split("\n")
    return [] if tags.empty?

    tags.map do |tag|
      # Get the date of the tag
      date = `git log -1 --format=%ai #{tag}`.chomp
      
      # Get all commits between this tag and the previous one
      previous_tag = tags[tags.index(tag) + 1]
      range = previous_tag ? "#{previous_tag}..#{tag}" : tag
      
      commits = `git log #{range} --format=%s --grep="^Merge"`.split("\n")
      changes = commits.map do |commit|
        commit.gsub(/^Merge pull request #\d+ from \S+ /, '')
      end

      {
        version: tag,
        date: Date.parse(date),
        changes: changes
      }
    end
  rescue StandardError => e
    Rails.logger.error("Error generating changelog: #{e.message}")
    []
  end
end

# Create a custom configuration object
class VersionConfig
  class << self
    attr_accessor :version, :changelog
  end
end

# Initialize version and changelog
VersionConfig.version = VersionInfo.get_version
VersionConfig.changelog = VersionInfo.get_changelog

# Make them accessible through Rails.application.config
Rails.application.config.to_prepare do
  Rails.application.config.define_singleton_method(:version) { VersionConfig.version }
  Rails.application.config.define_singleton_method(:changelog) { VersionConfig.changelog }
end 
