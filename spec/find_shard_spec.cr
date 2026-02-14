require "./spec_helper"
require "../src/find_shard/core"

describe FindShard do
  describe ".parse_shards" do
    it "parses a single shard from HTML" do
      html = File.read("spec/fixtures/shards_search.html")
      shards = FindShard.parse_shards(html)

      shards.size.should eq(1)

      shard = shards.first
      shard.name.should eq("owner/repo")
      shard.description.should eq("A test shard description")
      shard.stars.should eq(1234)
      shard.forks.should eq(567)
      shard.open_issues.should eq(89)
      shard.used_by.should eq(10)
      shard.dependencies.should eq(5)
      shard.last_activity.should eq("2 days ago")
      shard.topics.should eq(["crystal", "test"])
      shard.url.should eq("https://shards.info/github/owner/repo")
      shard.avatar_url.should eq("https://avatars.githubusercontent.com/u/123?v=4")
      shard.archived.should be_true
    end

    it "handles missing optional elements" do
      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="shards__shard">
          <h2 class="shards__shard_name">
            <a href="/github/owner/repo">owner/repo</a>
          </h2>
          <p class="shards__shard_desc"></p>
          <div class="shards__shard_stats">
            <ul>
              <li>1 star</li>
              <li>2 forks</li>
              <li>3 open issues</li>
              <li>Used by 4</li>
              <li>5 dependencies</li>
            </ul>
          </div>
        </div>
      </body>
      </html>
      HTML

      shards = FindShard.parse_shards(html)
      shards.size.should eq(1)

      shard = shards.first
      shard.description.should be_nil
      shard.avatar_url.should be_nil
      shard.archived.should be_false
      shard.topics.should be_empty
      shard.last_activity.should be_nil
      shard.stars.should eq(1)
      shard.forks.should eq(2)
      shard.open_issues.should eq(3)
      shard.used_by.should eq(4)
      shard.dependencies.should eq(5)
    end

    it "parses stats with various number formats" do
      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="shards__shard">
          <h2 class="shards__shard_name">
            <a href="/github/test/test">test/test</a>
          </h2>
          <div class="shards__shard_stats">
            <ul>
              <li>0 stars</li>
              <li>1,000 forks</li>
              <li>2,345,678 open issues</li>
              <li>Used by 9,999</li>
              <li>0 dependencies</li>
              <li>just now</li>
            </ul>
          </div>
        </div>
      </body>
      </html>
      HTML

      shards = FindShard.parse_shards(html)
      shard = shards.first
      shard.stars.should eq(0)
      shard.forks.should eq(1000)
      shard.open_issues.should eq(2345678)
      shard.used_by.should eq(9999)
      shard.dependencies.should eq(0)
      shard.last_activity.should eq("just now")
    end

    it "returns empty array when no shards found" do
      html = "<html><body>No shards here</body></html>"
      shards = FindShard.parse_shards(html)
      shards.should be_empty
    end
  end
end
