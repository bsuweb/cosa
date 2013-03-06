=begin

Get all of the urls from the urls table that include the domain
For each of these urls, get their path
  ex) http://www.bemidjistate.edu/academics/ would be:
      /academics/
Create any necessary directories
Save the page in an html file
  Name should be index.html unless specified


=end




require 'sequel'
require './options'
require 'logger'

class Database

  def snapshot(path, domain)
    $LOG = Logger.new("logfile.log")
    # Get current directory
    dir = Dir.pwd

    # Get a list of all sites that contain the domain from the config file
    paths = @urls.where(Sequel.like(:url, "%#{ domain[7..-1] }%" ))
    paths_hash = {}
    # Remove the domain from each url, and add each new url and its response
    # to a hash
    paths.each { |x| paths_hash[x[:url].gsub(domain, "")] = x[:response] }
    # paths_hash.each { |x| puts x }

    # Create directories
    paths_hash.each do |path|
      [".css", ".html", ".php", ".js", ".cfm"].any? do |ext|
        if path[0].include?(ext)
          # create dir
          FileUtils.mkdir_p "#{ dir }#{ path[0] }"
          # create file
        else
          # create dir
          FileUtils.mkdir_p "#{ dir }#{ path[0] }"
          Dir.chdir("#{ dir }#{ path[0] }")
          file = File.open('index.html', 'w')
          file.puts(path[1])
          file.close
        end
      end
    end
    # paths.each do |path|
    #   [".html", ".css", ".php", ".js"].any? do |ext|
    #     if path.include?(ext)
    #       path = path[/^.+/]
    #       FileUtils.mkdir_p "#{ dir }#{ path}"
    #     else
    #       FileUtils.mkdir_p "#{ dir }#{ path }"
    #     end
    #   end
    # end

  end

end
