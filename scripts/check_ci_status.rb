#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'json'
require 'octokit'

# Check CI status for a GitHub repository commit
#
# Usage:
#   ruby check_ci_status.rb --repo owner/repo --sha COMMIT_SHA
#
# Exit codes:
#   0 - All required CI checks passed
#   1 - One or more CI checks failed
#   2 - CI checks still pending
#   3 - Error occurred

class CIChecker
  def initialize(token: nil)
    @client = Octokit::Client.new(access_token: token || ENV['GITHUB_TOKEN'])
    @client.auto_paginate = true
  end

  # Check CI status for a specific commit
  #
  # @param repo [String] Repository in "owner/name" format
  # @param sha [String] Commit SHA
  # @param required_contexts [Array<String>] Specific status contexts to check (optional)
  # @return [Symbol] :success, :failure, :pending, or :error
  def check_commit(repo, sha, required_contexts: [])
    status = @client.combined_status(repo, sha)

    # If specific contexts required, filter by them
    if required_contexts.any?
      statuses = status.statuses.select { |s| required_contexts.include?(s.context) }
      return :pending if statuses.empty? && required_contexts.any?

      states = statuses.map(&:state)
    else
      states = status.statuses.map(&:state)
    end

    # Determine overall state
    if states.empty?
      :pending
    elsif states.any? { |s| %w[failure error].include?(s) }
      :failure
    elsif states.any? { |s| s == 'pending' }
      :pending
    else
      :success
    end
  rescue Octokit::Error => e
    puts "Error checking CI status: #{e.message}"
    :error
  end

  # Check specific workflow run status
  #
  # @param repo [String] Repository in "owner/name" format
  # @param run_id [Integer] GitHub Actions workflow run ID
  # @return [Symbol] :success, :failure, :pending, or :error
  def check_workflow_run(repo, run_id)
    run = @client.workflow_run(repo, run_id)

    case run.status
    when 'completed'
      run.conclusion == 'success' ? :success : :failure
    when 'in_progress', 'queued', 'pending'
      :pending
    else
      :error
    end
  rescue Octokit::Error => e
    puts "Error checking workflow run: #{e.message}"
    :error
  end
end

def main
  options = {
    repo: nil,
    sha: nil,
    workflow_run: nil,
    required_contexts: [],
    token: ENV['GITHUB_TOKEN']
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby check_ci_status.rb [options]'

    opts.on('--repo REPO', 'Repository in owner/name format') do |repo|
      options[:repo] = repo
    end

    opts.on('--sha SHA', 'Commit SHA to check') do |sha|
      options[:sha] = sha
    end

    opts.on('--workflow-run ID', Integer, 'Workflow run ID to check') do |id|
      options[:workflow_run] = id
    end

    opts.on('--required CONTEXTS', 'Comma-separated required status contexts') do |contexts|
      options[:required_contexts] = contexts.split(',')
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
  unless options[:repo]
    puts 'Error: --repo argument required'
    exit 3
  end

  unless options[:token]
    puts 'Error: GitHub token required (set GITHUB_TOKEN env or use --token)'
    exit 3
  end

  checker = CIChecker.new(token: options[:token])

  if options[:workflow_run]
    status = checker.check_workflow_run(options[:repo], options[:workflow_run])
  elsif options[:sha]
    status = checker.check_commit(options[:repo], options[:sha], required_contexts: options[:required_contexts])
  else
    puts 'Error: Either --sha or --workflow-run required'
    exit 3
  end

  # Output result and exit with appropriate code
  case status
  when :success
    puts 'CI status: SUCCESS - All checks passed'
    exit 0
  when :failure
    puts 'CI status: FAILURE - One or more checks failed'
    exit 1
  when :pending
    puts 'CI status: PENDING - Checks still running'
    exit 2
  when :error
    puts 'CI status: ERROR - Could not determine status'
    exit 3
  end
end

main if __FILE__ == $PROGRAM_NAME
