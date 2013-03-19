require 'sequel'
require './options'
require 'logger'

class Snapshot

  # snap = Snapshot.new( {:path => path, :domain => domain, :urls => urls} )
  def initialize(options)
    $LOG = Logger.new("logfile.log")
    opts = {:path => Dir.pwd, :domain => nil, :urls => nil}.merge(options)

    if File.exists?(opts[:path])
      Dir.chdir(opts[:path])
    else
      FileUtils.mkdir_p opts[:path]
    end

    # Get a list of all sites that contain the domain from the config file
    paths = opts[:urls].where(Sequel.like(:url, "%#{ opts[:domain][7..-1] }%"))
    # Remove the domain from each url, add add each new url and its response
    # to a hash as long as its status code is >= 200 and less than 400
    paths_hash = {}
    paths.each do |x|
      if x[:status].to_i < 400 && x[:status].to_i >= 200
        paths_hash[x[:url].gsub(opts[:domain], "")] = x[:response]
      end
    end

    paths_hash.each do |path|
      # if path contains no file extension
      if File.extname(path[0]).empty?
        create_directory("#{ opts[:path] }#{ path[0] }")
        create_file("index.html", path[1], "#{ opts[:path] }#{path[0]}")
      else
        path_array = path[0].reverse.split('/', 2).collect(&:reverse).reverse
        create_directory("#{ opts[:path] }#{ path_array[0] }")
        create_file(path_array[1], path[1], "#{ opts[:path] }#{ path_array[0] }")
      end
    end
  end

  def create_file(name, content, path)
    Dir.chdir(path)
    unless File.exists? name
      File.open(name, "w") { |f| f.write(content) }
    end
  end

  def create_directory(path)
    arr = path.reverse.split('/', 2).collect(&:reverse).reverse
    unless File.exists? "#{ arr[1] }"
      FileUtils.mkdir_p "#{ path }"
    end
  end

end
