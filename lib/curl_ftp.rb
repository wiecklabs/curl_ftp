require 'uri'
require 'open3'

module CurlFtp

  class CurlExecutionError < StandardError
    attr_reader :command, :errors, :error_code

    def initialize(command, errors)
      @command, @errors = command, errors

      @error_code = if errors =~ /curl\:\s\((\d+)\)/
        $1.to_i
      else
        nil
      end

      super("The command #{command} generated the following error message: #{errors}")
    end
  end

  class Connection

    attr_reader :uri

    ##
    # Arguments
    #   - uri: FTP URI to connect to, such as "ftp://user:password@site.com"
    #   - logger: optional Logger instance
    #   - curl_options: optional array of arguments to be passed to curl when
    #                   executing commands, e.g. ["--disable-epsv"]
    ##
    def initialize(uri, logger = nil, curl_options = [])
      @curl_options = curl_options
      @uri = (uri.is_a?(String) ? URI.parse(uri) : uri)
      @root = @uri + '/'
      @pwd = @uri.path
      
      @logger = logger
    end
    
    def log(level, message)
      return unless @logger
      @logger.send(level, message)
    end

    def ls(path = '')
      root = @root + File.join(@pwd, path)
      results = curl(root, '')

      results.map { |r| Entry.parse(root, r) }
    end

    def exists?(path)
      path = File.join(@pwd, path)

      if File.extname(path) == ""
        # To check for existence of directories, they must have a trailing slash.
        root = @root + File.join(path, "/")
      else
        root = @root + path
      end

      curl(root, '-I ')

      true
    rescue CurlExecutionError
      raise unless [9, 19].include?($!.error_code)

      return false
    end

    def mkdir(path)
      path = File.join(@pwd, path)

      return false if exists?(path)

      curl(@root, "-Q \"MKD #{path}\" -I")

      true
    end

    def mkdir_p(path)
      path = File.join(@pwd, path)
      path = File.dirname(path) unless File.extname(path) == ""

      components = path.split(/(?=\/)/)
      folders_to_create = []

      until exists?(File.join(components.join, "/"))
        folders_to_create.unshift(components.join)
        components.pop
      end

      return false if folders_to_create.empty?

      curl(@root, folders_to_create.map { |folder| "-Q \"MKD #{folder}\"" }.join(" ") + " -I")

      true
    end

    def rmdir(path)
      path = File.join(@pwd, path)

      return false unless exists?(path)

      curl(@root, "-Q \"RMD #{path}\" -I")

      true
    end

    def rm(path)
      curl(@root, "-X \"DELE #{File.join(@pwd, path)}\"")
    end

    def get(filename)
      curl(@root + File.join(@pwd, filename), "-o \"#{URI.escape(filename)}\"")
    end

    def last_modified(filename)
      results = curl(@root + URI.escape(File.join(@pwd, filename)), "-I")
      if results && results =~ /Last-Modified:\s(.*)/
        Time.parse($1)
      else
        nil
      end
    end

    def put(local_path, remote_path)
      curl(@root + File.join(@pwd, remote_path), "-T \"#{local_path}\"")
    end

    private

    def curl(uri, command)
      # -s enables silent mode (no progress information)
      # -S enables writing of errors to stderr
      #
      execute("curl #{@curl_options.join(" ")} '#{uri.to_s}' --user '#{URI.unescape(uri.userinfo)}' -s -S #{command}")
    end

    def execute(command)
      log :debug, "CurlFtp Executing: #{command}"

      result = ''
      errors = ''

      Open3.popen3(command) do |stdin, stdout, stderr|
        result = stdout.read
        errors = stderr.read
      end

      unless errors.empty?
        raise CurlExecutionError.new(command, errors)
      end

      result
    end

  end

  class Entry

    attr_reader :uri, :permissions, :uid, :gid, :size, :last_modified, :name

    def initialize(uri, permissions, uid, gid, size, last_modified, name)
      @uri, @permissions, @uid, @gid, @size, @last_modified, @name = uri, permissions, uid, gid, size, last_modified, name
    end

    class << self

      def parse(root, listing)
        month_names = (Date::MONTHNAMES + Date::ABBR_MONTHNAMES).compact.map { |name| name.upcase }

        if listing =~ /^(d[rwxsg-]+)\s*((folder)\s+(\d+))?.*?((#{month_names.join('|')})\s+\d+\s+(\d+\:\d+|\d+))\s(.*)/i
          FolderEntry.new(root + URI.escape($8), $1, nil, nil, $4.to_i, parse_date($5), $8)
        elsif listing =~ /^([^d][rwxsg-]+)\s+?(\d)\s+(\d+)\s+(\d+)\s+(\d+).*?((#{month_names.join('|')})\s+\d+\s+(\d+\:\d+|\d+))\s(.*)/i
          FileEntry.new(root + URI.escape($9), $1, $3, $4, $5.to_i, parse_date($6), $9)
        elsif listing =~ /^([^d][rwxsg-]+)\s+?(\d)\s+(\d+)\s+(\d+).*?((#{month_names.join('|')})\s+\d+\s+(\d+\:\d+|\d+))\s(.*)/i
          FileEntry.new(root + URI.escape($8), $1, nil, nil, $3.to_i, parse_date($5), $8)
        else
          return nil
        end
      end

      def parse_date(date_string)
        Time.parse(date_string) rescue DateTime.parse("#{date_string} #{Date.today.year}")
      end

    end

  end

  class FolderEntry < Entry

    def inspect
      %Q{<FolderEntry permission: #{permissions}, uid: #{uid}, gid: #{gid}, last_modified: #{last_modified.to_s} />}
    end

  end

  class FileEntry < Entry

    def inspect
      %Q{<FileEntry permission: #{permissions}, uid: #{uid}, gid: #{gid}, size: #{size}, last_modified: #{last_modified.to_s} />}
    end

  end

end
