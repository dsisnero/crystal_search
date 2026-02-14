module HTTPClient
  extend self

  DEFAULT_USER_AGENT = "crystal_search/0.1.0"
  DEFAULT_TIMEOUT    = 30.seconds

  def get(url : String, user_agent : String = DEFAULT_USER_AGENT, max_redirects : Int32 = 10) : String
    response = request("GET", url, user_agent, max_redirects: max_redirects)
    raise "HTTP request failed: #{response.status_code}" unless response.success?
    response.body
  end

  def post_form(url : String, form_data : String, user_agent : String = DEFAULT_USER_AGENT, max_redirects : Int32 = 10) : String
    headers = HTTP::Headers{
      "Content-Type" => "application/x-www-form-urlencoded",
      "User-Agent"   => user_agent,
      "Accept"       => "text/html",
    }
    response = request("POST", url, user_agent, headers, form_data, max_redirects)
    raise "HTTP request failed: #{response.status_code}" unless response.success?
    response.body
  end

  def request(method : String, url : String, user_agent : String = DEFAULT_USER_AGENT, headers : HTTP::Headers? = nil, body : String? = nil, max_redirects : Int32 = 10) : HTTP::Client::Response
    current_url = url
    visited = Set(String).new

    while max_redirects > 0
      break if visited.includes?(current_url)
      visited.add(current_url)

      uri = URI.parse(current_url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = DEFAULT_TIMEOUT
      client.read_timeout = DEFAULT_TIMEOUT

      request_headers = headers || HTTP::Headers.new
      request_headers["User-Agent"] = user_agent
      request_headers["Accept"] = "text/html" unless request_headers.has_key?("Accept")

      response = case method
                 when "GET"
                   client.get(uri.request_target, headers: request_headers)
                 when "POST"
                   client.post(uri.request_target, headers: request_headers, body: body.not_nil!)
                 else
                   raise "Unsupported HTTP method: #{method}"
                 end

      if response.status_code >= 300 && response.status_code < 400
        location = response.headers["Location"]?
        if location
          current_url = resolve_redirect_url(uri, location)
          max_redirects -= 1
          next
        end
      end

      return response
    end

    raise "Too many redirects"
  end

  private def resolve_redirect_url(base_uri : URI, location : String) : String
    if location.starts_with?("http://") || location.starts_with?("https://")
      location
    elsif location.starts_with?("/")
      "#{base_uri.scheme}://#{base_uri.host}#{location}"
    else
      base_path = base_uri.path
      base_path = base_path[0...base_path.rindex('/')]? if base_path.includes?('/')
      resolved_path = "#{base_path}/#{location}".gsub(/\/+/, '/')
      "#{base_uri.scheme}://#{base_uri.host}#{resolved_path}"
    end
  end
end
