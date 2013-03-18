require 'sequel'
require './options'
require 'logger'

class Snapshot

  # snap = Snapshot.new( {:path => path, :domain => domain, :urls => urls} )
  def initialize(options)
    $LOG = Logger.new("logfile.log")
    opts = {:path => Dir.pwd,
            :domain => nil,
            :urls => nil
           }.merge(options)
    Dir.chdir(Dir.pwd)

    # Get a list of all sites that contain the domain from the config file
    paths = opts[:urls].where(Sequel.like(:url, "%#{ opts[:domain][7..-1] }%" ))
    # Remove the domain from each url, add add each new url and its response to a hash
    paths_hash = {}
    paths.each { |x| paths_hash[x[:url].gsub(opts[:domain], "")] = x[:response] }

    paths_hash.each do |path|
      # if path ends in "/"
      $LOG.debug("#{path[0]}")
      if path[0][-1, 1] == "/"
        create_directory("#{ opts[:path] }#{ path[0] }")
        create_file("index.html", path[1], "#{ opts[:path] }#{path[0]}")
      else
        path_array = path[0].reverse.split('/', 2).collect(&:reverse).reverse
        new_path = path_array[0]
        file_name = path_array[1]
        create_directory("#{ opts[:path] }#{ new_path }")
        create_file(file_name, path[1], "#{ opts[:path] }#{new_path}")
      end
    end
  end

  def create_file(name, content, path)
    Dir.chdir(path)
    unless File.exists? name
      file = File.open(name, "w")
      file.puts(content)
      file.close
    end
  end

  def create_directory(path)
    unless Dir.exists? "#{path}"
      FileUtils.mkdir_p "#{ path }"
    end
  end

end
