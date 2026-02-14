require "http/client"
require "lexbor"
require "json"
require "option_parser"
require "../http_client"

module CrystalDoc
  class ShardResult
    include JSON::Serializable

    getter name : String
    getter stars : Int32
    getter url : String
    getter doc_url : String

    def initialize(@name, @stars, @url, @doc_url)
    end
  end

  class TypeInfo
    include JSON::Serializable

    getter id : String
    getter name : String
    getter url : String
    getter parent : Bool

    def initialize(@id, @name, @url, @parent)
    end
  end

  class Documentation
    include JSON::Serializable

    getter shard_name : String
    getter version : String
    getter description : String?
    getter types : Array(TypeInfo)
    getter content : String

    def initialize(@shard_name, @version, @description, @types, @content)
    end
  end

  def self.search_shards(query : String) : Array(ShardResult)
    encoded_query = URI.encode_www_form(query)
    url = "https://www.crystaldoc.info/search"
    form_data = "q=#{encoded_query}"
    html = HTTPClient.post_form(url, form_data, user_agent: "crystal_doc/0.1.0 (Crystal)")
    parse_search_results(html)
  end

  def self.parse_search_results(html : String) : Array(ShardResult)
    parser = Lexbor::Parser.new(html)
    results = [] of ShardResult

    parser.css("li").each do |li|
      link = li.css("a").first?
      next unless link

      href = link.attribute_by("href")
      next unless href && href.starts_with?("/github/")

      name = link.inner_text.strip
      doc_url = "https://www.crystaldoc.info#{href}"

      # Extract stars from pill-box
      stars_pill = li.css("span.pill").find do |span|
        span.inner_text.includes?("⭐") || span.inner_text.includes?("⍟")
      end

      stars = 0
      if stars_pill
        stars_text = stars_pill.inner_text.gsub(/[^0-9]/, "")
        stars = stars_text.to_i32 unless stars_text.empty?
      end

      results << ShardResult.new(
        name: name,
        stars: stars,
        url: "https://github.com/#{name}",
        doc_url: doc_url
      )
    end

    results
  end

  def self.fetch_documentation(shard_url : String) : Documentation
    html = HTTPClient.get(shard_url, user_agent: "crystal_doc/0.1.0 (Crystal)")
    parse_documentation(html, shard_url)
  end

  def self.parse_documentation(html : String, shard_url : String) : Documentation
    parser = Lexbor::Parser.new(html)

    # Extract shard name and version
    title_elem = parser.css("title").first?
    shard_name = "unknown"
    version = "unknown"

    if title_elem
      title = title_elem.inner_text
      if match = title.match(/(.+?)\s+v([\d.]+)/)
        shard_name = match[1]
        version = match[2]
      end
    end

    # Extract description from meta tag
    description = nil
    meta_desc = parser.css("meta[name='description']").first?
    description = meta_desc.try(&.attribute_by("content"))

    # Extract types from sidebar
    types = [] of TypeInfo
    parser.css("div.types-list li").each do |li|
      link = li.css("a").first?
      next unless link

      id = li["data-id"]? || ""
      name = li["data-name"]? || link.inner_text.strip
      href = link.attribute_by("href") || ""
      url = href.empty? ? "" : "https://www.crystaldoc.info#{href}"
      parent = li["class"]?.to_s.includes?("parent")

      types << TypeInfo.new(id, name, url, parent)
    end

    # Extract main content
    main_content = parser.css("div.main-content").first?
    content = main_content.try(&.inner_text.strip) || ""

    Documentation.new(
      shard_name: shard_name,
      version: version,
      description: description,
      types: types,
      content: content
    )
  end

  def self.run
    if ARGV.size == 0 || ARGV.includes?("--help") || ARGV.includes?("-h")
      puts <<-HELP
      Usage: crystal_doc <command> [options] <query>

      Commands:
        search <query>    Search for shards
        fetch <name/url>  Fetch documentation for a shard
        get <query>       Search and fetch first result

      Options:
        -f, --format FORMAT  Output format: json, text, markdown (default: json)
        -p, --pretty         Pretty print JSON output
        -h, --help           Show this help
        -v, --version        Show version

      Examples:
        crystal_doc search kemal
        crystal_doc fetch kemalcr/kemal
        crystal_doc get kemal --format text
      HELP
      exit ARGV.size == 0 ? 1 : 0
    end

    if ARGV.includes?("--version") || ARGV.includes?("-v")
      puts "crystal_doc 0.1.0"
      exit 0
    end

    mode = ARGV[0]?
    query = nil
    format = "json"
    pretty = false

    # Parse options after command
    option_start = 2
    ARGV.each_with_index do |arg, i|
      if arg == "-f" || arg == "--format"
        format = ARGV[i + 1]? || "json"
      elsif arg == "-p" || arg == "--pretty"
        pretty = true
      end
    end

    if mode.nil?
      STDERR.puts "Error: Command required"
      exit 1
    end

    query = ARGV[1]?
    if query.nil?
      STDERR.puts "Error: Query required for command '#{mode}'"
      exit 1
    end

    # Skip options for query extraction
    if query.starts_with?("-")
      STDERR.puts "Error: Query required after command '#{mode}'"
      exit 1
    end

    begin
      case mode
      when "search"
        results = search_shards(query)
        output_search_results(results, format, pretty)
      when "fetch"
        doc_url = normalize_shard_url(query)
        doc = fetch_documentation(doc_url)
        output_documentation(doc, format, pretty)
      when "get"
        results = search_shards(query)
        if results.empty?
          STDERR.puts "No results found for '#{query}'"
          exit 1
        end
        doc = fetch_documentation(results.first.doc_url)
        output_documentation(doc, format, pretty)
      else
        STDERR.puts "Unknown command: #{mode}"
        exit 1
      end
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      exit 1
    end
  end

  private def self.normalize_shard_url(input : String) : String
    if input.starts_with?("http://") || input.starts_with?("https://")
      return input
    elsif input.includes?("/")
      # Assume owner/repo format
      return "https://www.crystaldoc.info/github/#{input}"
    else
      # Just repo name, need to search first
      results = search_shards(input)
      if results.empty?
        raise "No shard found with name '#{input}'"
      end
      return results.first.doc_url
    end
  end

  private def self.output_search_results(results : Array(ShardResult), format : String, pretty : Bool)
    case format
    when "json"
      if pretty
        json_output = JSON.build(indent: "  ") do |json|
          json.array do
            results.each do |result|
              result.to_json(json)
            end
          end
        end
        puts json_output
      else
        puts results.to_json
      end
    when "text", "markdown"
      results.each_with_index do |result, i|
        puts "#{i + 1}. #{result.name} (#{result.stars} ⭐)"
        puts "   GitHub: #{result.url}"
        puts "   Docs: #{result.doc_url}"
        puts
      end
    else
      STDERR.puts "Unknown format: #{format}"
      exit 1
    end
  end

  private def self.output_documentation(doc : Documentation, format : String, pretty : Bool)
    case format
    when "json"
      if pretty
        json_output = JSON.build(indent: "  ") do |json|
          doc.to_json(json)
        end
        puts json_output
      else
        puts doc.to_json
      end
    when "text"
      puts "Shard: #{doc.shard_name}"
      puts "Version: #{doc.version}"
      if desc = doc.description
        puts "Description: #{desc}"
      end
      puts
      puts "Types (#{doc.types.size}):"
      doc.types.each do |type|
        indent = type.parent ? "  " : ""
        puts "#{indent}- #{type.name}: #{type.url}"
      end
      puts
      puts "Content:"
      puts doc.content
    when "markdown"
      puts "# #{doc.shard_name} v#{doc.version}"
      if desc = doc.description
        puts "\n#{desc}\n"
      end
      puts "\n## Types\n"
      doc.types.each do |type|
        indent = type.parent ? "" : "  "
        puts "#{indent}- [#{type.name}](#{type.url})"
      end
      puts "\n## Documentation\n"
      puts doc.content
    else
      STDERR.puts "Unknown format: #{format}"
      exit 1
    end
  end
end
