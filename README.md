# Crystal Search

A collection of CLI tools for searching and retrieving information about Crystal
shards and documentation.

## Tools

### `find_shard`

Search [shards.info](https://shards.info) for Crystal packages and return
structured JSON results.

### `crystal_doc`

Search and fetch documentation from
[crystaldoc.info](https://www.crystaldoc.info) with support for multiple output
formats (JSON, text, markdown).

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/dsisnero/crystal_search.git
   cd crystal_search
   ```

2. Install dependencies:

   ```bash
   shards install
   ```

3. Build the tools:

   ```bash
   shards build
   ```

The binaries will be available in the `bin/` directory:

- `bin/find_shard`
- `bin/crystal_doc`

## Usage

### `find_shard`

Search for shards and output JSON:

```bash
./bin/find_shard http
```

Use `-p` for pretty-printed JSON:

```bash
./bin/find_shard -p http
```

**Example output:**

```json
[
  {
    "name": "martenframework/marten",
    "description": "The pragmatic web framework.",
    "stars": 464,
    "forks": 0,
    "open_issues": 16,
    "used_by": 25,
    "dependencies": 9,
    "last_activity": "9 days ago",
    "topics": [
      "crystal",
      "web-framework",
      "web",
      "http",
      "server",
      "crystal-lang",
      "crystal-language",
      "framework",
      "backend"
    ],
    "url": "https://github.com/martenframework/marten",
    "avatar_url": "https://avatars.githubusercontent.com/u/124774736?v=4",
    "archived": false
  }
]
```

**Help and version:**

```bash
./bin/find_shard -h
./bin/find_shard -v
```

### `crystal_doc`

Three commands are available:

#### `search` - Search for shard documentation

```bash
./bin/crystal_doc search http -f json
```

#### `fetch` - Fetch documentation from a specific URL

```bash
./bin/crystal_doc fetch https://www.crystaldoc.info/github/henrikac/httpcat -f text
```

#### `get` - Search and fetch the first result's documentation

```bash
./bin/crystal_doc get http -f markdown
```

**Output formats:** Use `-f` flag with `json`, `text`, or `markdown` (default:
json).

**Example search output (JSON):**

```json
[
  {
    "name": "feifanzhou/robust_http.cr",
    "stars": 0,
    "url": "https://github.com/feifanzhou/robust_http.cr",
    "doc_url": "https://www.crystaldoc.info/github/feifanzhou/robust_http.cr"
  }
]
```

**Example fetch output (text):**

```text
Shard: httpcat
Version: 1.0.3

Types (1):
- top level namespace: https://www.crystaldoc.infotoplevel.html

Content:
httpcat is a fun tool to translate http status codes.

Installation
Start by cloning the repository and then build the project...
```

**Help and version:**

```bash
./bin/crystal_doc -h
./bin/crystal_doc -v
```

## Development

### Dependencies

- **lexbor** - HTML parsing (runtime dependency)
- **ameba** - Linter (development dependency)

### Building

```bash
shards build
```

### Testing

Run the test suite:

```bash
crystal spec
```

### Linting

Run Ameba to check code style:

```bash
ameba
```

### Project Structure

- `src/find_shard.cr` - Main implementation of `find_shard`
- `src/crystal_doc.cr` - Main implementation of `crystal_doc`
- `spec/` - Test files
- `bin/` - Built binaries (after `shards build`)

## Contributing

1. Fork it (<https://github.com/dsisnero/crystal_search/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Dominic Sisneros](https://github.com/dsisnero) - creator and maintainer

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file
for details.
