require 'sequel'
require 'yaml'
require 'uri'
require 'trollop'
# require './cosa_new'
# require './cli'

class Database
  attr_accessor :opts, :db, :urls, :links, :queue, :SHELF, :domain, :start_time, :output
  def set_opts(opts)
    # Load configuration file
    # Used to load the base domain to be crawled, and the path to the database
    if opts[:config]
      # Use the given config file if it exists, otherwise create one
      if File.exists?(opts[:config])
        config = YAML::load(File.open(opts[:config]))
      else
        config = YAML::load(File.open(create_config))
      end
    # Else load the default config file
    else
      config = YAML::load(File.open('config.yaml'))
    end

    if opts[:init] then config = YAML::load(File.open(create_config)) end

    @db = Sequel.connect(config['db_path'])
    @urls = db[:urls]
    @links = db[:links]
    @queue = db[:queue]
    @domain = config['domain']
    @start_time = Time.now

    if config['shelf_life']
      @@SHELF = config['shelf_life']
    else
      @@SHELF = 86400
    end

    @output = "default"
    @output = "silent" if opts[:silent]
    @output = "verbose" if opts[:verbose]

    # Clear Queue
    if opts[:clear_queue] then queue.delete end

    # List Queue
    if opts[:queue] then queue.each { |x| puts x[:url] } end

    # Add to Queue
    if opts[:add] then opts[:add].each { |x| insert_data_into(queue, [ x, '', 1 ]) } end

    # List CSS
    if opts[:css]
      temp = []
      @links.where(:type => 'css').each { |x| temp << x[:to_url] }
      temp.uniq!.each { |y| puts y }
    end

    # List to
    if opts[:to] then @links.where(:to_url => opts[:to]).each { |x| puts x[:from_url] } end

    # List from
    if opts[:from] then @links.where(:from_url => opts[:from]).each { |x| puts x[:to_url] } end

    # List response time
    if opts[:response_time]
      urls = @urls.where{ response_time > opts[:response_time] }.each { |x| puts "#{ x[:url] } | #{ x[:response_time] }"} end

    # List unresponsive
    if opts[:unresponsive] then @urls.where{ status > 500 }.each { |x| puts "#{x[:url] } => #{ x[:status] }" } end

    # List broken links
    if opts[:broken]
      @urls.where(:status => 404).each do |bad_link|
        puts "BAD LINK: #{ bad_link[:url] } LINKED TO BY:\n"
        @links.where(:to_url => bad_link[:url]).each { |x| puts "#{ x[:from_url] }" }
        puts "\n"
      end
    end

    # List age
    if opts[:age] then @urls.where{ accessed < Time.parse(opts[:age]) }.each { |x| puts "#{ x[:url] } | #{ x[:accessed] }" } end

    # Start Crawling
    if opts[:crawl]
      if opts[:crawl].length == 1
      # 1 Argument, gets the url to add to the queue.
        insert_data_into(@queue, [ opts[:crawl],'', 1 ])
      elsif opts[:crawl].length == 2
      # 2 Arguments, gets the url to add to the queue and the pattern to use
      # when checking pages.
      pattern = URI.join( opts[:crawl][0], opts[:crawl][1] ).to_s
      insert_data_into(@queue, [ opts[:crawl][0], opts[:crawl][1], 1 ])
      else
      end
    else
      Process.exit
    end

  end

  def create_config
    strings = [
              "No config file given, or exists. Would you like to create one? (y/n) ",
              "Enter the base domain to be crawled. (ex: http://www.example.com) ",
              "Enter a shelf life(time between crawls) in hours. Default is 24 hours. ",
              "Enter the absolute path for the database (leave blank for default) ",
              "Example: Users/username/Documents/cosa/data/database.sqlite",
              "Enter the name of your config file:"
              ]

    # Ask to create new config
    puts strings[0]
    ans = $stdin.gets[0,1].chomp.downcase
    if ans == 'y'
      # Enter the base domain
      puts strings[1]
      domain = $stdin.gets.chomp.downcase
      while true
        # Get the shelf life, check to make sure it is an integer
        puts strings[2]
        shelf = $stdin.gets.chomp
        if shelf.numeric? then break else puts "Please enter an integer." end
      end
      # Get the path of the database
      puts "#{ strings[3] }\n#{ strings[4] }"
      db_path = $stdin.gets.chomp.downcase
      # Get new file name
      puts strings[5]
      name = $stdin.gets.chomp

      config_file = File.open(name, "w")
      config_file.puts("# Cosa config file\n\ndomain: #{ domain }\n\n# Amount of time between crawls on the same page\n# 86400 seconds by default (1 day)\nshelf_life: #{ shelf.to_i * 3600 }\n\n# Ex) sqlite:///Users/username/Documents/cosa/data/webcrawler.sqlite\ndb_path: #{ db_path }")
      config_file.close
    else
      Process.exit
    end
    return name
  end
end