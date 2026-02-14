require "./spec_helper"
require "../src/crystal_doc/core"

describe CrystalDoc do
  describe ".parse_search_results" do
    it "parses search results with stars" do
      html = File.read("spec/fixtures/crystaldoc_search.html")
      results = CrystalDoc.parse_search_results(html)

      results.size.should eq(3) # fourth link is not /github/ prefix

      first = results[0]
      first.name.should eq("owner/repo")
      first.stars.should eq(42)
      first.url.should eq("https://github.com/owner/repo")
      first.doc_url.should eq("https://www.crystaldoc.info/github/owner/repo")

      second = results[1]
      second.name.should eq("another/example")
      second.stars.should eq(100)
      second.url.should eq("https://github.com/another/example")
      second.doc_url.should eq("https://www.crystaldoc.info/github/another/example")

      third = results[2]
      third.name.should eq("no-stars/no-stars")
      third.stars.should eq(0)
      third.url.should eq("https://github.com/no-stars/no-stars")
      third.doc_url.should eq("https://www.crystaldoc.info/github/no-stars/no-stars")
    end

    it "returns empty array when no results" do
      html = "<html><body>No results</body></html>"
      results = CrystalDoc.parse_search_results(html)
      results.should be_empty
    end
  end

  describe ".parse_documentation" do
    it "parses documentation page" do
      html = File.read("spec/fixtures/crystaldoc_doc.html")
      doc = CrystalDoc.parse_documentation(html, "https://www.crystaldoc.info/github/owner/repo")

      doc.shard_name.should eq("TestShard")
      doc.version.should eq("1.2.3")
      doc.description.should eq("A test shard description")
      doc.types.size.should eq(2)

      first_type = doc.types[0]
      first_type.id.should eq("type1")
      first_type.name.should eq("TypeOne")
      first_type.url.should eq("https://www.crystaldoc.info/github/owner/repo/v1.2.3/TypeOne.html")
      first_type.parent.should be_true

      second_type = doc.types[1]
      second_type.id.should eq("type2")
      second_type.name.should eq("TypeTwo")
      second_type.url.should eq("https://www.crystaldoc.info/github/owner/repo/v1.2.3/TypeTwo.html")
      second_type.parent.should be_false

      doc.content.should contain("TestShard")
      doc.content.should contain("This is the main content of the documentation.")
    end

    it "handles missing elements" do
      html = <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Untitled</title>
      </head>
      <body>
        <div class="main-content">
          Some content
        </div>
      </body>
      </html>
      HTML

      doc = CrystalDoc.parse_documentation(html, "https://example.com")
      doc.shard_name.should eq("unknown")
      doc.version.should eq("unknown")
      doc.description.should be_nil
      doc.types.should be_empty
      doc.content.should eq("Some content")
    end
  end
end
