#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'json'
require 'octokit'
require 'fileutils'
require 'yaml'

# Collect artifacts from GitHub Actions workflow runs
#
# Usage:
#   ruby collect_artifacts.rb --repo owner/repo --workflow-run ID --platform linux,macos,windows
#
# Outputs JSON array of artifact paths to stdout

class ArtifactCollector
  def initialize(token: nil, temp_dir: nil)
    @client = Octokit::Client.new(access_token: token || ENV['GITHUB_TOKEN'])
    @temp_dir = temp_dir || Dir.mktmpdir('github-artifacts-')
    @platform_patterns = load_platform_patterns
  end

  # Load platform detection patterns from config
  #
  # @return [Hash] Platform patterns
  def load_platform_patterns
    default_patterns = {
      'linux' => ['*linux*', '*ubuntu*', '*debian*', '*rhel*'],
      'macos' => ['*macos*', '*darwin*', '*mac*', '*osx*'],
      'windows' => ['*windows*', '*win*', '*msvc*']
    }

    config_path = File.join(__dir__, 'config.yml')
    if File.exist?(config_path)
      config = YAML.load_file(config_path)
      config['platform_patterns'] || default_patterns
    else
      default_patterns
    end
  end

  # List artifacts from a workflow run
  #
  # @param repo [String] Repository in "owner/name" format
  # @param workflow_run_id [Integer] Workflow run ID
  # @return [Array<Hash>] List of artifact metadata
  def list_artifacts(repo, workflow_run_id)
    response = @client.workflow_run_artifacts(repo, workflow_run_id)
    artifacts = response.artifacts
    artifacts.map do |artifact|
      {
        id: artifact.id,
        name: artifact.name,
        size: artifact.size_in_bytes,
        url: artifact.archive_download_url,
        created_at: artifact.created_at,
        expired: artifact.expired
      }
    end
  rescue Octokit::Error => e
    puts "Error listing artifacts: #{e.message}"
    []
  end

  # Filter artifacts by platform
  #
  # @param artifacts [Array<Hash>] Artifact metadata
  # @param platforms [Array<String>] Platforms to include (linux, macos, windows)
  # @return [Array<Hash>] Filtered artifacts
  def filter_by_platform(artifacts, platforms)
    return artifacts if platforms.empty?

    artifacts.select do |artifact|
      platforms.any? do |platform|
        patterns = @platform_patterns[platform.downcase] || []
        patterns.any? { |pattern| File.fnmatch(pattern, artifact[:name].downcase, File::FNM_CASEFOLD) }
      end
    end
  end

  # Download an artifact
  #
  # @param repo [String] Repository in "owner/name" format
  # @param artifact_id [Integer] Artifact ID
  # @param destination [String] Destination filename
  # @return [String, nil] Path to downloaded file or nil on error
  def download_artifact(repo, artifact_id, destination)
    # GitHub requires accept header for artifact download
    @client.get("repos/#{repo}/actions/artifacts/#{artifact_id}/zip",
                accept: 'application/vnd.github.v3+json') do |response|
      if response.status == 302
        # Follow redirect
        redirect_url = response.headers['location']
        download_from_url(redirect_url, destination)
      else
        # Direct download
        File.binwrite(destination, response.body)
      end
    end

    destination
  rescue StandardError => e
    puts "Error downloading artifact #{artifact_id}: #{e.message}"
    nil
  end

  # Download from URL (follows redirects)
  def download_from_url(url, destination)
    require 'net/http'
    require 'uri'

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    request = Net::HTTP::Get.new(uri.request_uri)
    # Add headers to match typical GitHub API client
    request['User-Agent'] = 'Octokit Ruby Gem'
    request['Accept'] = 'application/vnd.github.v3+json'
    # Add authorization token if available (though SAS token should be enough)
    request['Authorization'] = "token #{@client.access_token}" if @client.access_token

    response = http.request(request)

    raise "Download failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    File.binwrite(destination, response.body)
  end

  # Download multiple artifacts
  #
  # @param repo [String] Repository
  # @param artifacts [Array<Hash>] Artifact metadata
  # @return [Array<String>] Paths to downloaded files
  def download_artifacts(repo, artifacts)
    downloaded = []

    artifacts.each do |artifact|
      next if artifact[:expired]

      filename = File.join(@temp_dir, "#{artifact[:name]}.zip")
      puts "Downloading #{artifact[:name]} (#{format_size(artifact[:size])})..."

      downloaded << filename if download_artifact(repo, artifact[:id], filename)
    end

    downloaded
  end

  # Clean up temporary directory
  def cleanup
    FileUtils.rm_rf(@temp_dir) if Dir.exist?(@temp_dir)
  end

  # Format file size for display
  def format_size(bytes)
    return '0 B' if bytes.nil? || bytes.zero?

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
    workflow_run: nil,
    platforms: [],
    token: ENV['GITHUB_TOKEN'],
    output_dir: nil,
    keep: false
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby collect_artifacts.rb [options]'

    opts.on('--repo REPO', 'Repository in owner/name format') do |repo|
      options[:repo] = repo
    end

    opts.on('--workflow-run ID', Integer, 'Workflow run ID') do |id|
      options[:workflow_run] = id
    end

    opts.on('--platforms LIST', 'Comma-separated platforms (linux,macos,windows)') do |list|
      options[:platforms] = list.split(',')
    end

    opts.on('--output-dir DIR', 'Output directory for artifacts') do |dir|
      options[:output_dir] = dir
    end

    opts.on('--token TOKEN', 'GitHub token (default: GITHUB_TOKEN env)') do |token|
      options[:token] = token
    end

    opts.on('--keep', 'Keep temporary directory (for debugging)') do
      options[:keep] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  # Validate arguments
  unless options[:repo] && options[:workflow_run]
    puts 'Error: --repo and --workflow-run arguments required'
    exit 1
  end

  unless options[:token]
    puts 'Error: GitHub token required (set GITHUB_TOKEN env or use --token)'
    exit 1
  end

  collector = ArtifactCollector.new(token: options[:token])

  begin
    # List artifacts
    artifacts = collector.list_artifacts(options[:repo], options[:workflow_run])

    if artifacts.empty?
      puts "No artifacts found for workflow run #{options[:workflow_run]}"
      exit 1
    end

    puts "Found #{artifacts.size} artifacts"

    # Filter by platform
    filtered = collector.filter_by_platform(artifacts, options[:platforms])

    if filtered.empty?
      puts "No artifacts match platforms: #{options[:platforms].join(', ')}"
      puts "Available artifacts: #{artifacts.map { |a| a[:name] }.join(', ')}"
      exit 1
    end

    puts "Filtered to #{filtered.size} artifacts for platforms: #{options[:platforms].join(', ')}"

    # Download artifacts
    downloaded = collector.download_artifacts(options[:repo], filtered)

    if downloaded.empty?
      puts 'Failed to download any artifacts'
      exit 1
    end

    puts "Downloaded #{downloaded.size} artifacts to #{collector.instance_variable_get(:@temp_dir)}"

    # Move to output directory if specified
    if options[:output_dir]
      FileUtils.mkdir_p(options[:output_dir])
      downloaded.each do |file|
        dest = File.join(options[:output_dir], File.basename(file))
        FileUtils.mv(file, dest)
      end
      puts "Artifacts moved to #{options[:output_dir]}"
    end

    # Output JSON array of paths
    result = {
      artifacts: downloaded.map { |path| File.basename(path) },
      directory: options[:output_dir] || collector.instance_variable_get(:@temp_dir),
      count: downloaded.size
    }

    puts JSON.pretty_generate(result)
  ensure
    collector.cleanup unless options[:keep]
  end
end

main if __FILE__ == $PROGRAM_NAME
