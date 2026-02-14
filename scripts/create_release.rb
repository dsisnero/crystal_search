#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'json'
require 'octokit'
require 'fileutils'
require 'yaml'

# Create GitHub release and upload artifacts
#
# Usage:
#   ruby create_release.rb --repo owner/repo --tag v1.0.0 --artifacts path/to/artifacts
#
# Creates a GitHub release with optional release notes and artifact uploads

class ReleaseCreator
  def initialize(token: nil)
    @client = Octokit::Client.new(access_token: token || ENV['GITHUB_TOKEN'])
    @client.auto_paginate = true
  end

  # Create a GitHub release
  #
  # @param repo [String] Repository in "owner/name" format
  # @param tag [String] Tag name
  # @param name [String, nil] Release name (defaults to tag)
  # @param body [String, nil] Release notes/description
  # @param draft [Boolean] Create as draft release
  # @param prerelease [Boolean] Mark as prerelease
  # @return [Sawyer::Resource] Created release
  def create_release(repo, tag, name: nil, body: nil, draft: false, prerelease: false)
    begin
      # Check if release already exists
      existing = @client.release_for_tag(repo, tag)
      if existing
        puts "Release already exists for tag #{tag}"
        return existing
      end
    rescue Octokit::NotFound
      # Release doesn't exist, proceed
    end

    puts "Creating release #{tag}#{' (draft)' if draft}#{' (prerelease)' if prerelease}"

    release = @client.create_release(
      repo,
      tag,
      name: name || tag,
      body: body || generate_release_notes(repo, tag),
      draft: draft,
      prerelease: prerelease
    )

    puts "Release created: #{release.html_url}"
    release
  end

  # Generate release notes from git history
  #
  # @param repo [String] Repository
  # @param tag [String] Current tag
  # @return [String] Markdown release notes
  def generate_release_notes(repo, tag)
    # Try to get previous tag
    tags = @client.tags(repo).map(&:name)
    current_index = tags.index(tag)

    previous_tag = (tags[current_index + 1] if current_index && current_index + 1 < tags.size)

    # Generate notes using GitHub API
    notes = @client.generate_release_notes(
      repo,
      tag_name: tag,
      previous_tag_name: previous_tag
    )

    notes.body
  rescue StandardError => e
    puts "Note: Could not generate release notes: #{e.message}"
    "## Release #{tag}\n\n*Artifacts attached for multiple platforms*"
  end

  # Upload artifact to release
  #
  # @param release [Sawyer::Resource] Release object
  # @param filepath [String] Path to artifact file
  # @param label [String, nil] Custom label for artifact
  # @return [Sawyer::Resource] Uploaded asset
  def upload_artifact(release, filepath, label: nil)
    filename = File.basename(filepath)
    content_type = content_type_for(filename)
    size = File.size(filepath)

    puts "Uploading #{filename} (#{format_size(size)})..."

    asset = @client.upload_asset(
      release.url,
      filepath,
      content_type: content_type,
      name: filename,
      label: label
    )

    puts "  ✓ Uploaded: #{asset.browser_download_url}"
    asset
  rescue StandardError => e
    puts "  ✗ Failed to upload #{filename}: #{e.message}"
    nil
  end

  # Upload multiple artifacts
  #
  # @param release [Sawyer::Resource] Release object
  # @param artifacts_dir [String] Directory containing artifacts
  # @param pattern [String] File pattern to match
  # @return [Array<Sawyer::Resource>] Uploaded assets
  def upload_artifacts(release, artifacts_dir, pattern: '*')
    uploaded = []

    Dir.glob(File.join(artifacts_dir, pattern)).each do |filepath|
      next unless File.file?(filepath)

      # Determine label based on platform
      label = platform_label_for(File.basename(filepath))

      asset = upload_artifact(release, filepath, label: label)
      uploaded << asset if asset
    end

    uploaded
  end

  # Determine content type for file
  def content_type_for(filename)
    case File.extname(filename).downcase
    when '.zip' then 'application/zip'
    when '.tar.gz', '.tgz' then 'application/gzip'
    when '.tar' then 'application/x-tar'
    when '.gz' then 'application/gzip'
    when '.deb' then 'application/vnd.debian.binary-package'
    when '.rpm' then 'application/x-rpm'
    when '.dmg' then 'application/x-apple-diskimage'
    when '.pkg' then 'application/x-newton-compatible-pkg'
    when '.exe' then 'application/x-msdownload'
    when '.msi' then 'application/x-msi'
    when '.appimage' then 'application/x-executable'
    else 'application/octet-stream'
    end
  end

  # Create platform label from filename
  def platform_label_for(filename)
    filename = filename.downcase

    if filename.include?('linux')
      'Linux'
    elsif filename.include?('macos') || filename.include?('darwin') || filename.include?('osx')
      'macOS'
    elsif filename.include?('windows') || filename.include?('win')
      'Windows'
    elsif filename.include?('x86_64') || filename.include?('amd64')
      'x86_64'
    elsif filename.include?('arm64') || filename.include?('aarch64')
      'ARM64'
    end
  end

  # Format file size for display
  def format_size(bytes)
    return '0 B' if bytes.zero?

    units = %w[B KB MB GB TB]
    size = bytes.to_f
    unit = 0

    while size >= 1024 && unit < units.size - 1
      size /= 1024
      unit += 1
    end

    "#{size.round(2)} #{units[unit]}"
  end
end

def main
  options = {
    repo: nil,
    tag: nil,
    artifacts_dir: nil,
    name: nil,
    body: nil,
    draft: false,
    prerelease: false,
    token: ENV['GITHUB_TOKEN'],
    pattern: '*'
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby create_release.rb [options]'

    opts.on('--repo REPO', 'Repository in owner/name format') do |repo|
      options[:repo] = repo
    end

    opts.on('--tag TAG', 'Release tag (e.g., v1.0.0)') do |tag|
      options[:tag] = tag
    end

    opts.on('--artifacts DIR', 'Directory containing artifacts') do |dir|
      options[:artifacts_dir] = dir
    end

    opts.on('--name NAME', 'Release name (defaults to tag)') do |name|
      options[:name] = name
    end

    opts.on('--body TEXT', 'Release notes/description') do |body|
      options[:body] = body
    end

    opts.on('--draft', 'Create as draft release') do
      options[:draft] = true
    end

    opts.on('--prerelease', 'Mark as prerelease') do
      options[:prerelease] = true
    end

    opts.on('--pattern PATTERN', 'File pattern for artifacts (default: *)') do |pattern|
      options[:pattern] = pattern
    end

    opts.on('--token TOKEN', 'GitHub token (default: GITHUB_TOKEN env)') do |token|
      options[:token] = token
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  # Validate arguments
  unless options[:repo] && options[:tag]
    puts 'Error: --repo and --tag arguments required'
    exit 1
  end

  unless options[:token]
    puts 'Error: GitHub token required (set GITHUB_TOKEN env or use --token)'
    exit 1
  end

  creator = ReleaseCreator.new(token: options[:token])

  begin
    # Create release
    release = creator.create_release(
      options[:repo],
      options[:tag],
      name: options[:name],
      body: options[:body],
      draft: options[:draft],
      prerelease: options[:prerelease]
    )

    # Upload artifacts if directory specified
    if options[:artifacts_dir] && Dir.exist?(options[:artifacts_dir])
      puts "\nUploading artifacts from #{options[:artifacts_dir]}..."
      artifacts = creator.upload_artifacts(
        release,
        options[:artifacts_dir],
        pattern: options[:pattern]
      )

      puts "\nUploaded #{artifacts.size} artifacts"
    else
      puts "\nNo artifacts directory specified, skipping upload"
    end

    # Output release info
    result = {
      release: {
        id: release.id,
        tag_name: release.tag_name,
        name: release.name,
        html_url: release.html_url,
        draft: release.draft,
        prerelease: release.prerelease,
        created_at: release.created_at
      },
      artifacts_count: artifacts&.size || 0
    }

    puts "\n" + JSON.pretty_generate(result)
  rescue StandardError => e
    puts "Error creating release: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
