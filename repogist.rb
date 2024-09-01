#!/usr/bin/env ruby
require 'date'
require 'digest'
require 'open3'
require 'openssl'
require 'optparse'
require 'socket'
require 'yaml'

# Use local vendor dir if it exists (`make gem`)
vendor_dir = "#{File.dirname(__FILE__)}/vendor"
if Dir.exist? vendor_dir
  require 'rubygems'
  Gem.paths = {
    'GEM_PATH' => [
      File.expand_path(vendor_dir),
      *Gem.paths.path,
    ].join(':')
  }
end

require 'octokit'
require 'jwt'

Class.new do
  VERSION = '0.1.0'
  DEFAULT_CONFIG_PATHS = [
    format('%s/.config/repogist/repogist.yml', Dir.home),
    '/etc/repogist.yml',
  ]
  CONTENT_DIR = 'content'
  JWT_HASH_ALG = 'RS256'
  JWT_EXPIRATION_S = 600

  def initialize
    @flags = {}
    @filenames = []
    @config_path = nil
    @config = {}
    @branch = nil
    @filename_read = nil
    @now_ts = DateTime.now
  end

  def run
    parse_flags
    read_config
    validate_config
    content = read_content
    push_content content
  end

  def parse_flags
    parser = OptionParser.new do |opts|
      opts.banner = <<~EOD
        Usage: repogist [options] [filename]
        Usage: ... | repogist [options]

      EOD
      # $ gist --help
      # ...
      # Usage: gist [-o|-c|-e] [-p] [-s] [-R] [-d DESC] [-u URL]
      #                           [--skip-empty] [-P] [-f NAME|-t EXT]* FILE*
      #        gist --login
      #        gist [-l|-r]
      # 
      #         --login                      Authenticate gist on this computer.
      #     -f, --filename [NAME.EXTENSION]  Sets the filename and syntax type.
      #     -t, --type [EXTENSION]           Sets the file extension and syntax type.
      #     -p, --private                    Makes your gist private.
      #         --no-private
      #     -d, --description DESCRIPTION    Adds a description to your gist.
      #     -s, --shorten                    Shorten the gist URL using git.io.
      #     -u, --update [ URL | ID ]        Update an existing gist.
      #     -c, --copy                       Copy the resulting URL to the clipboard
      #     -e, --embed                      Copy the embed code for the gist to the clipboard
      #     -o, --open                       Open the resulting URL in a browser
      #         --no-open
      #         --skip-empty                 Skip gisting empty files
      #     -P, --paste                      Paste from the clipboard to gist
      #     -R, --raw                        Display raw URL of the new gist
      #     -l, --list [USER]                List all gists for user
      #     -r, --read ID [FILENAME]         Read a gist and print out the contents
      #         --delete [ URL | ID ]        Delete a gist
      #     -h, --help                       Show this message.
      #     -v, --version                    Print the version.
      opts.on('-f', '--filename=FNAME', 'Sets the filename and syntax type.')
      opts.on('-t', '--type=EXT', 'Sets the file extension and syntax type.')
      opts.on('-d', '--description=DESC', 'Adds a description to your gist (commit message).')
      opts.on('--skip-empty', 'Skip gisting empty files')
      opts.on('-v', '--version', 'Print the version.') do
        printf("repogist %s\n", VERSION)
        exit
      end
      opts.on('-h', '--help', 'Show this message.') do
        puts opts
        exit
      end
      # TODO: Support other gist flags
    end
    @filenames = parser.order!(into: @flags)
  end

  def read_config
    # Try `config_path` if specified, then try default config paths
    # Stop at the first one that loads
    [ @config_path, *DEFAULT_CONFIG_PATHS ].compact.each do |config_path|
      @config = YAML.safe_load_file(config_path) rescue next
      break
    end
  end

  def validate_config
    fail "Failed to read #{@config_path}" unless @config
    %w(app_id private_key installation_id repo_name repo_branch).each do |field|
      fail "Expected config field #{field}" unless @config[field]
    end
  end

  def read_content
    if !$stdin.isatty
      # Read from stdin if not a tty
      content = STDIN.read
    elsif @filenames.length > 0
      # Read file is specified
      # TODO: Read multiple files?
      @filename_read = @filenames[0]
      return File.read(@filename_read)
    else
      fail 'No filename supplied and no stdin'
    end
  end

  def push_content(content)
    client = get_client
    repo_name = @config['repo_name']
    repo_branch = @config['repo_branch']
    repo_path = get_repo_path(content)

    res = nil
    begin
      # Create
      res = client.create_contents(
        repo_name,
        repo_path,
        get_commit_message,
        content,
        :branch => repo_branch
      )
    rescue Octokit::UnprocessableEntity
      # Update?
      existing_file = client.contents(
        repo_name,
        :path => repo_path,
        :branch => repo_branch,
      )
      raise unless existing_file
      res = client.create_contents(
        repo_name,
        repo_path,
        get_commit_message,
        content,
        :branch => repo_branch,
        :sha => existing_file[:sha],
      )
    end

    fail 'Failed to push content' unless res

    # Print permalink
    html_url = res[:content][:html_url]
    commit_sha = res[:commit][:sha]
    permalink_url = html_url.sub(%r{/blob/[^/]+/}, "/blob/#{commit_sha}/")
    puts permalink_url
  end

  def get_client
    jwt = get_jwt(@config['app_id'])
    app = Octokit::Client.new(bearer_token: jwt)
    access_token = app.create_app_installation_access_token(@config['installation_id'])[:token]
    Octokit::Client.new(access_token: access_token)
  end

  def get_jwt(app_id)
    payload = {
      :iat => @now_ts.to_time.to_i,
      :exp => @now_ts.to_time.to_i + JWT_EXPIRATION_S,
      :iss => app_id,
    }
    priv_key = OpenSSL::PKey::RSA.new(@config['private_key'])
    JWT.encode(payload, priv_key, JWT_HASH_ALG)
  end

  def get_repo_path(content)
    # content/<username>/<filename>
    path = []
    path << CONTENT_DIR
    path << get_username
    path << get_filename(content)
    path.join('/')
  end

  def get_filename(content)
    # If specified as a flag, use that verbatim
    return @flags[:filename] if @flags[:filename]

    # If we read a file, use that filename, otherwise a random hex string
    fname = @filename_read || SecureRandom.hex(8)

    # If a type was specified, append we don't already have that extension
    fname << ".#{@flags[:type]}" if @flags[:type] && File.extname(fname) != ".#{@flags[:type]}"

    fname
  end

  def get_commit_message
    # `<username>` on `<hostname>` @ <timestamp>
    #
    # <description>
    format(
      '`%s` on `%s` @ %s%s',
      get_username,
      get_hostname,
      @now_ts.strftime('%+'),
      (@flags[:description] ? "\n\n#{@flags[:description]}" : ''),
    )
  end

  def get_hostname
    # Try `hostname -f`, falling back on `Socket.gethostname`
    hostname, _, status = Open3.capture3('hostname -f')
    if status == 0 && hostname.strip.length > 0
      hostname.strip
    else Socket.gethostname.strip.length > 0
      Socket.gethostname.strip
    else
      'unknown'
    end
  end

  def get_username
    Etc.getlogin
  end
end.new.run
