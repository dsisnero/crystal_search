require "http/client"
require "lexbor"
require "json"
require "option_parser"
require "../http_client"

module FindShard
  class Shard
    include JSON::Serializable

    getter name : String
    getter description : String?
    getter stars : Int32
    getter forks : Int32
    getter open_issues : Int32
    getter used_by : Int32
    getter dependencies : Int32
    getter last_activity : String?
    getter topics : Array(String)
    getter url : String
    getter avatar_url : String?
    getter archived : Bool

    def initialize(@name, @description, @stars, @forks, @open_issues, @used_by, @dependencies, @last_activity, @topics, @url, @avatar_url, @archived)
    end
  end

  def self.fetch_search_results(query : String) : String
    encoded_query = URI.encode_www_form(query)
    url = "https://shards.info/search?query=#{encoded_query}"
    HTTPClient.get(url, user_agent: "find_shard/0.1.0 (Crystal)")
  end

  def self.parse_shards(html : String) : Array(Shard)
    parser = Lexbor::Parser.new(html)
    shards = [] of Shard

    parser.css("div.shards__shard").each do |shard_div|
      # Extract name (owner/repo)
      name_link = shard_div.css("h2.shards__shard_name a").first?
      next unless name_link

      full_name = name_link.inner_text.strip
      href = name_link.attribute_by("href")
      url = "https://shards.info#{href}" if href

      # Extract description
      desc_elem = shard_div.css("p.shards__shard_desc").first?
      description = desc_elem.try(&.inner_text.strip).presence

      # Extract avatar URL
      avatar_img = shard_div.css("img.avatar").first?
      avatar_url = avatar_img.try(&.attribute_by("src"))

      # Check if archived
      archived_badge = shard_div.css("span.archived-badge").first?
      archived = !archived_badge.nil?

      # Extract topics
      topics = shard_div.css("a.badge.bg-secondary.text-monospace").map do |badge|
        badge.inner_text.strip
      end

      # Extract stats from the list
      stats = shard_div.css("div.shards__shard_stats ul li").map do |li|
        li.inner_text.strip
      end

      stars = extract_stat(stats, 0)
      forks = extract_stat(stats, 1)
      open_issues = extract_stat(stats, 2)
      used_by = extract_stat(stats, 3)
      dependencies = extract_stat(stats, 4)
      last_activity = extract_last_activity(stats)

      shards << Shard.new(
        name: full_name,
        description: description,
        stars: stars,
        forks: forks,
        open_issues: open_issues,
        used_by: used_by,
        dependencies: dependencies,
        last_activity: last_activity,
        topics: topics,
        url: url || "",
        avatar_url: avatar_url,
        archived: archived
      )
    end

    shards
  end

  private def self.extract_stat(stats : Array(String), index : Int32) : Int32
    return 0 if index >= stats.size

    stat = stats[index]
    # Extract numeric value (remove commas and non-digits)
    stat.gsub(/[^0-9]/, "").to_i32
  end

  private def self.extract_last_activity(stats : Array(String)) : String?
    return nil if stats.size < 6

    stats[5].strip
  end

  def self.run
    pretty = false
    query = nil

    OptionParser.parse do |parser|
      parser.banner = "Usage: find_shard <query> [options]"
      parser.on("-h", "--help", "Show this help") do
        puts parser
        puts "\nSearch for Crystal shards on shards.info and return results as JSON."
        puts "\nExample:"
        puts "  find_shard crystal"
        puts "  find_shard \"web framework\""
        exit
      end
      parser.on("-v", "--version", "Show version") do
        puts "find_shard 0.1.0"
        exit
      end
      parser.on("-p", "--pretty", "Pretty print JSON output") do
        pretty = true
      end
      parser.unknown_args do |args|
        if args.size != 1
          STDERR.puts "Error: Exactly one query argument required"
          STDERR.puts parser
          exit 1
        end
        query = args[0]
      end
    end

    begin
      html = fetch_search_results(query.not_nil!)
      shards = parse_shards(html)

      if pretty
        json_output = JSON.build(indent: "  ") do |json|
          json.array do
            shards.each do |shard|
              shard.to_json(json)
            end
          end
        end
        puts json_output
      else
        puts shards.to_json
      end
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      exit 1
    end
  end
end
