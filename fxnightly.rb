#!/usr/bin/env ruby
#
# WARNING:  this is a hackjob.
#
# A script to retrieve Firefox nightlies and
# unpacks it to the specified location.
# Also propagates symlinks from the ./plugins dir
#
# Jeffrey Lau
# 20090918

require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'

$N = File::basename $0
$VERSION = 0.02

class FxOpt

  BASE_URL = 'http://ftp.mozilla.org/pub/mozilla.org/firefox/nightly'

  BRANCHES = %w[
    latest-trunk
    latest-mozilla-1.9.1
    latest-mozilla-1.9.2
    latest-mozilla-2.0
    latest-mozilla-aurora
    latest-mozilla-central
    latest-tracemonkey
  ]

  BRANCH_ALIASES = {
    "trunk"        => "latest-trunk",
    "191"          => "latest-mozilla-1.9.1",
    "192"          => "latest-mozilla-1.9.2",
    "2"            => "latest-mozilla-2.0",
    "aurora"       => "latest-mozilla-aurora",
    "central"      => "latest-mozilla-central",
    "trace"        => "latest-tracemonkey",
  }

  PLATFORMS = %w[linux-i686 linux-x86_64 mac win32]

  DEFAULTS = {
    :install_root => File.join( ENV['HOME'], 'local', 'firefoxes' ),
    :locale       => 'en-US',
    :platform     => 'linux-x86_64',
    :base_url     => BASE_URL,
    :branch       => 'latest-trunk',
    :interactive  => false,
    :verbose      => false,
    :dryrun       => false,
  }

  #
  # Return a structure describing the options.
  #
  def self.parse( args )
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new( DEFAULTS )

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$N} [options]"

      opts.separator ""
      opts.separator "Specific options:"

      # Mandatory argument.
      opts.on(
        "-o",
        "--override FILE",
        "Use the bzip2 tarball of Firefox at local FILE.",
        "  TODO: make it HTTP/FTP aware."
      ) do |override|
        options.override = override
      end

      opts.on(
        "--base-url URL",
        "Specify the base URL of the remote end.",
        "  (default:  #{DEFAULTS[:base_url]})"
      ) do |base_url|
        options.base_url = base_url
      end

      opts.on(
        "-r",
        "--install-root DIR",
        "Extract the Firefox installation at DIR.",
        "  (default:  #{DEFAULTS[:install_root]})"

      ) do |install_root|
        options.install_root = install_root
      end


      # Platform
      opts.on(
        "-p",
        "--platform PLATFORM", PLATFORMS,
        "Specify the PLATFORM of the Firefox.",
        "  (#{PLATFORMS.join( ', ' )})",
        "  (default:  #{DEFAULTS[:platform]})"

      ) do |p|
        options.platform = p
      end

      # Localization
      opts.on(
        "-l",
        "--locale LOCALE",
        "Specify the LOCALE of the Firefox.",
        "  (default:  #{DEFAULTS[:locale]})"
      ) do |l|
        options.locale = l
        # ensure the capitalization is correct
        options.locale.sub!( /-([^-]*)/ ) {|subloc| subloc.upcase }
      end


      # Keyword completion.  We are specifying a specific set of arguments (CODES
      # and CODE_ALIASES - notice the latter is a Hash), and the user may provide
      # the shortest unambiguous text.
      # code_list = ( CODE_ALIASES.keys + CODES ).join( ',' )
      # opts.on(
        # "--code CODE", CODES, CODE_ALIASES,
        # "Select encoding", "  (#{code_list})"
      # ) do |encoding|
        # options.encoding = encoding
      # end
      branch_list = ( BRANCH_ALIASES.keys + BRANCHES ).join( ', ' )
      opts.on(
        "-b", "--branch BRANCH", BRANCHES, BRANCH_ALIASES,
        "Select the branch of Firefox", "  (#{branch_list})",
        "  (default:  #{DEFAULTS[:branch]})"

      ) do |branch|
        options.branch = branch
      end

      # Optional argument with keyword completion.
      # opts.on(
        # "--type [TYPE]", [:text, :binary, :auto],
        # "Select transfer type (text, binary, auto)"
      # ) do |t|
        # options.transfer_type = t
      # end

      # Boolean switch.
      opts.on(
        "-i", "--[no-]interactive",
        "Run interactively",
        "  (default:  #{DEFAULTS[:interactive]})"

      ) do |i|
        options.interactive = i
      end

      # Boolean switch.
      opts.on(
        "-v", "--[no-]verbose",
        "Run verbosely",
        "  (default:  #{DEFAULTS[:verbose]})"

      ) do |v|
        options.verbose = v
      end

      # Boolean switch.
      opts.on(
        "-d", "--dry-run",
        "Download the package, but don't install anything",
        "  (default:  #{DEFAULTS[:dryrun]})"

      ) do |d|
        options.dryrun = d
      end

      opts.separator ""
      opts.separator "Common options:"

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on_tail(
        "-h", "--help",
        "Show this message"
      ) do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail(
        "--version", "Show version"
      ) do
        puts $VERSION
        exit
      end

      # Do some clever things to determine where the tarball is.
      # options.tarball = options.base_url + '/asdf'
    end

    opts.parse!( args )
    options
  end  # parse()

end  # class FxOpt

# A RemoteFile represents a remote file with a URL.
class RemoteFile

  attr_accessor :url, :name, :last_modified, :size, :description
  NAME_RE = /^(.+-[^-.]*)(\.)([^-]+)$/

  def initialize( hash={:url=>''} )
    @url           = hash[:url]
    @name          = File.basename( @url )
    @last_modified = hash[:last_modified]
    @size          = hash[:size]
    @description   = hash[:description]
  end
  alias :date :last_modified

  def to_s
    return @url
  end

  def inspect
    "#<#{self.class}: url:#{@url.inspect} name:#{@name.inspect} last_modified:#{@last_modified.inspect} size:#{@size.inspect} description:#{@description.inspect}>"
  end

  # Infer the extension of the file.
  def extension
    return split_name[-1]
  end
  alias :ext :extension

  # convenience method for string manip on the name
  def split_name 
    return @name.scan( NAME_RE ).flatten
  end

end

class FxDownloader
  require 'uri'

  attr_reader :all_remote_files
  DEFAULT_EXTS = {
    :"linux-i686"   => 'tar.bz2',
    :"linux-x86_64" => 'tar.bz2',
    :mac            => 'dmg',
    :win32          => 'zip',
  }

  # accepts a Hash or an OpenStruct object.
  def initialize( options=nil )
    @all_remote_files = []
    @opts = case options
      when OpenStruct then options
      when Hash then OpenStruct.new( options )
      else OpenStruct.new( FxOpt::DEFAULTS )
      end
    pp @opts if @opts.verbose
  end

  # returns the URL to fetch the directory listing from.
  def dir_listing_url
    return URI.parse( "#{@opts.base_url}/#{@opts.branch}/" )
  end

  # returns the URL to fetch the package from
  def get_remote_dir_listing

    file_list = []

    # Probe the directory listing
    dirlist_html = self.class.http_fetch( dir_listing_url ).body

    @all_remote_files = extract_remote_files_listing( dirlist_html )

    # filter out unwanted files.
    # gives us >1 files: a ``complete.mar'' and one/two more files (dmg/tar.bz2/exe & zip).
    @relevant_files = @all_remote_files.reject do |file|
      # puts file.name
      file.name !~ /#{@opts.locale}/ ||
      file.name !~ /#{@opts.platform}/
    end

    return @relevant_files
  end

  # returns THE file to retrieve.
  def the_file

    # but which file do we REALLY want?
    wanted_file = @relevant_files.select do |file|
        # printf "%s!!!\n", file.url
      if file.ext == DEFAULT_EXTS[@opts.platform.to_sym]
        file.url.to_s
      end
    end[-1] # select the last match (good enough??)

    return wanted_file
  end

  # Download the file.
  def fetch_file( file_uri, dest_root, filename=nil )
    case file_uri
    when RemoteFile then
      uri = file_uri.url
    when String then
      uri = file_uri
    end

    if filename.nil?
      filename = File.basename( uri )
      case file_uri
      when RemoteFile then
      end
    end

    puts "Fetching #{uri}."
    
    File.open( File.join( dest_root, filename ), 'w' ) do |local_file|
      local_file.write self.class.http_fetch( uri ).body
      puts "Fetched."
    end
  end

  # Given a string of HTML, extracts what's relevant and
  # returns an array of +RemoteFile+s.
  def extract_remote_files_listing_hpricot( html_str )
    require 'rubygems'
    require 'hpricot'
    require 'date'  # to parse date from strings

    doc = Hpricot( html_str )
    ary = []  # accumulator

    # get the relevant bits
    ( doc/"tr" ).each do |tr|
      tds = ( tr/"td")
      next unless tds[1]
      rf      = RemoteFile.new
      rf.name = ( tds[1]/"a" ).inner_html
      rf.url  = URI.parse( "#{@opts.base_url}/#{@opts.branch}/#{( tds[1]/"a" ).first.attributes['href']}" )
      begin
        rf.last_modified  = DateTime.parse( tds[2].inner_html )
      rescue ArgumentError
        # Date unparseable. Skip it.
        next
      end
      rf.size     = tds[3].inner_html.gsub( /^\s+/, '' )
      # rf.description    = tds[4].inner_html

      # Collect
      ary << rf
    end
    return ary
  end

  # Given a string of HTML, extracts what's relevant and
  # returns an array of +RemoteFile+s.
  def extract_remote_files_listing( html_str )
    require 'rubygems'
    require 'nokogiri'
    require 'date'  # to parse date from strings

    doc = Nokogiri::HTML( html_str )
    ary = []  # accumulator

    # get the relevant bits
    ( doc/"tr" ).each do |tr|
      tds = ( tr/"td")
      next unless tds[1]
      rf      = RemoteFile.new
      rf.name = ( tds[1]/"a" ).inner_html
      rf.url  = URI.parse( "#{@opts.base_url}/#{@opts.branch}/#{( tds[1]/"a" ).first.attributes['href']}" )
      begin
        rf.last_modified  = DateTime.parse( tds[2].inner_html )
      rescue ArgumentError
        # Date unparseable. Skip it.
        next
      end
      rf.size     = tds[3].inner_html.gsub( /^\s+/, '' )
      # rf.description    = tds[4].inner_html

      # Collect
      ary << rf
    end
    return ary
  end

  # An HTTP fetch method that follows redirection
  #
  # Returns a Net::HTTPResponse object.
  # Call .body to get its content.
  # 
  # @url  http://www.ruby-doc.org/stdlib/libdoc/net/http/rdoc/classes/Net/HTTP.html
  def self.http_fetch( uri_str, limit=10 )
    require 'net/http'

    # You should choose better exception.
    raise RedirectException, 'HTTP redirect too deep' if limit == 0

    response = Net::HTTP.get_response( uri_str )
    return case response
      when Net::HTTPSuccess then response
      when Net::HTTPRedirection then self.http_fetch( response['location'], limit - 1 )
      else response.error!
      end
  end
end

# This object installs the Firefox distribution.
class FxInstaller

  def initialize( options=nil )
    @opts = case options
      when OpenStruct then options
      when Hash then OpenStruct.new( options )
      else OpenStruct.new( FxOpt::DEFAULTS )
      end
  end

  # extract the archive to dest.
  def extract_archive( dest )
  end

  # the method to install...
  def install( source=nil )

    # check if source is supplied.
    if source.nil?
      source = ( @opts.source || @opts.override )
    end

    begin
      require 'bz2'
    rescue LoadError
      # cannot find the libbzip2 binding.
      # Use system calls.
      warn "Cannot find `bz2' binding."
      extract_bz2_by_system( source )
    end
    # TODO: implement for the bz2 binding.
    puts "yay"
    extract_bz2_by_binding( source )
  end

  :private
  # Extract archive via Ruby's `system'.
  # First, create directory if not exists.
  def extract_bz2_by_system( source )

    # synthesize the full install directory path
    @install_dir = File.join(@opts.install_root, @opts.branch)

    # create directory if not exists:-
    if !File.directory? @install_dir
      begin
        Dir.mkdir @install_dir unless @opts.dryrun
      rescue Errno::EEXIST
      rescue Error => e
        warn e
      end
    end

    system( "tar", "xjf", source, "-C", @install_dir, "--overwrite" ) unless @opts.dryrun

    if @opts.dryrun || $?.exitstatus == 0
      puts "Extracted."
    else
      raise Exception.new( "system tar xjf failed?" )
    end

    # NOTE: kinda want to keep the 'firefox' subdirectory, e.g.
    #
    #   trunk
    #     `- firefox
    #
    # # hack to move the firefox installation to the proper directory
    # # XXX: BUGGO FIXME  what happen !!!
    # File.rename( @opts.install_root, @install_dir ) unless @opts.dryrun
  end

  # Extract archive via Ruby's bz2 binding.
  def extract_bz2_by_binding( source )
    begin
      require 'bz2'
    rescue LoadError => e
      return
    end
    # blah
  end
end

class RedirectException < Exception; end

if __FILE__ == $0
  options = FxOpt.parse( ARGV )

  # check if want override
  if options.override
    # check if override target exists
    if File.exists?( options.override )
      # File exists!
      # Install it.
      puts "Exists."
      FxInstaller.new( options ).install
    else
      raise "File `#{options.override}' doesn't exist!"
    end
  else
    fxd = FxDownloader.new( options )
    puts fxd.get_remote_dir_listing.inspect
    puts thefile = fxd.the_file
    # add the date into the filename
    filename = lambda {|ary|
        ary[-2..-1] = [ "-#{thefile.date.strftime( '%Y%m%d' )}", ary[-2..-1]]
        ary.join
      }.call( thefile.split_name )

    # fetch the file
    puts "fetching..."
    fxd.fetch_file( thefile, "/tmp", filename )

    # install the thing.
    puts "installing..."
    FxInstaller.new( options ).install( File.join( "/tmp", filename ))

    # done.
    puts "done."
  end
else

end
