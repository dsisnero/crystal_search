#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'json'

# Determine release tag from git or user input
#
# Usage:
#   ruby determine_release_tag.rb --auto          # Extract from git ref
#   ruby determine_release_tag.rb --tag v1.0.0    # Use provided tag
#   ruby determine_release_tag.rb --prompt        # Interactive prompt
#
# Outputs tag to stdout, exits with 0 on success, non-zero on error

class ReleaseTag
  # Semantic versioning regex (loose)
  SEMVER_REGEX = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/

  def initialize
    @git_ref = ENV['GITHUB_REF'] || ''
  end

  # Extract tag from git reference
  #
  # @return [String, nil] Tag name or nil if not a tag ref
  def from_git_ref
    if @git_ref.start_with?('refs/tags/')
      tag = @git_ref.sub('refs/tags/', '')
      return tag if valid_tag?(tag)
    end

    nil
  end

  # Get tag from environment variable
  #
  # @return [String, nil] Tag from env or nil
  def from_env
    tag = ENV['RELEASE_TAG'] || ENV['RELEASE_VERSION']
    return tag if tag && valid_tag?(tag)

    nil
  end

  # Validate tag format
  #
  # @param tag [String] Tag to validate
  # @return [Boolean] True if valid
  def valid_tag?(tag)
    return false unless tag.is_a?(String)
    return false if tag.empty?

    # Basic validation: alphanumeric, dots, dashes, plus, v prefix
    return false unless tag.match?(/^[vV]?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z\-.]+)?$/)

    # Semantic version validation
    !!tag.match(SEMVER_REGEX)
  end

  # Normalize tag format (ensure v prefix)
  #
  # @param tag [String] Tag to normalize
  # @return [String] Normalized tag
  def normalize_tag(tag)
    return tag if tag.start_with?('v', 'V')

    # Add v prefix if it looks like a version
    if tag.match?(/^\d+\.\d+\.\d+/)
      "v#{tag}"
    else
      tag
    end
  end

  # Interactive prompt for tag
  #
  # @return [String] User-provided tag
  def prompt_tag
    print 'Enter release version (e.g., v1.0.0): '
    tag = gets.chomp.strip

    until valid_tag?(tag)
      puts 'Invalid version format. Please use semantic versioning (e.g., v1.0.0, 2.1.0-beta.1)'
      print 'Enter release version: '
      tag = gets.chomp.strip
    end

    normalize_tag(tag)
  end

  # Get latest tag from git history
  #
  # @return [String, nil] Latest tag or nil
  def latest_git_tag
    tags = `git tag --sort=-v:refname 2>/dev/null`.lines.map(&:chomp)
    tags.find { |t| valid_tag?(t) }
  rescue StandardError
    nil
  end
end

def main
  options = {
    mode: nil,
    tag: nil,
    normalize: false
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby determine_release_tag.rb [options]'

    opts.on('--auto', 'Auto-detect from git ref or env') do
      options[:mode] = :auto
    end

    opts.on('--tag TAG', 'Use provided tag') do |tag|
      options[:mode] = :provided
      options[:tag] = tag
    end

    opts.on('--prompt', 'Interactive prompt') do
      options[:mode] = :prompt
    end

    opts.on('--normalize', 'Normalize tag format (ensure v prefix)') do
      options[:normalize] = true
    end

    opts.on('--latest', 'Get latest tag from git history') do
      options[:mode] = :latest
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  # Default mode if none specified
  options[:mode] ||= :auto

  tag_detector = ReleaseTag.new
  tag = nil

  case options[:mode]
  when :auto
    tag = tag_detector.from_git_ref || tag_detector.from_env

    unless tag
      puts 'Error: Could not auto-detect tag from git ref or env'
      puts "  GITHUB_REF: #{ENV['GITHUB_REF'] || '(not set)'}"
      puts "  RELEASE_TAG: #{ENV['RELEASE_TAG'] || '(not set)'}"
      puts "  RELEASE_VERSION: #{ENV['RELEASE_VERSION'] || '(not set)'}"
      exit 1
    end

  when :provided
    tag = options[:tag]

    unless tag_detector.valid_tag?(tag)
      puts "Error: Invalid tag format: #{tag}"
      puts '  Must be semantic version (e.g., v1.0.0, 2.1.0-beta.1)'
      exit 1
    end

  when :prompt
    tag = tag_detector.prompt_tag

  when :latest
    tag = tag_detector.latest_git_tag

    unless tag
      puts 'Error: No valid tags found in git history'
      exit 1
    end

  else
    puts "Error: Unknown mode: #{options[:mode]}"
    exit 1
  end

  # Normalize if requested
  tag = tag_detector.normalize_tag(tag) if options[:normalize]

  # Output tag
  puts tag
end

main if __FILE__ == $PROGRAM_NAME
