require 'sequel'
require 'yaml'
require 'uri'
require './snapshot'

class Database
  attr_accessor :opts, :db, :urls, :links, :queue, :SHELF, :domain, :start_time, :output, :crawled
  def initialize(opts)
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

    if File.exists?(config['db_path'])
      if config['db_path']
        @db = Sequel.connect("sqlite://#{ config['db_path']}")
      else
        @db = Sequel.connect(:adapter => 'mysql', :user => config['user'], :socket => config['sock'], :database => config['name'], :password => config['pass'])
      end
    else
      puts "The database listed in your config file does not exist. Would you like to create it? (y/n)"
      ans = $stdin.gets[0,1].chomp.downcase
      unless ans == 'y' then Process.exit end
      create_db('sqlite', nil, nil, nil, "#{config['db_path']}")
      @db = Sequel.connect("sqlite://#{ config['db_path'] }")
    end
    @crawled = 0
    @avg_response = 0
    @urls = db[:urls]
    @links = db[:links]
    @queue = db[:queue]
    @domain = config['domain']
    @exceptions = config['exceptions']
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
      @links.where(:type => 'css').group(:to_url).order{max(1)}.each { |x| puts x[:to_url] }
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
        puts "BAD LINK: #{ bad_link[:url] }\nLINKED TO BY:\n"
        @links.where(:to_url => bad_link[:url]).each { |x| puts "#{ x[:from_url] }" }
        puts "\n"
      end
    end

    # List abandoned links
    if opts[:abandoned]
      puts "Abandoned links:"
      @urls.each do |link|
        unless @links[:to_url => link[:url]]
          puts link[:url]
        end
      end
    end

    # List age
    if opts[:age] then @urls.where{ accessed < Time.parse(opts[:age]) }.each { |x| puts "#{ x[:url] } | #{ x[:accessed] }" } end

    if opts[:snapshot]
      snap = Snapshot.new({:path => opts[:snapshot], :domain => @domain, :urls => @urls})
    end

    # Crawl opt set, start crawling
    if opts[:crawl]
      if opts[:crawl].length == 1
        # 1 Argument, insert into queue
        insert_data_into(@queue, [ opts[:crawl],'', 1, 0 ])
      elsif opts[:crawl].length == 2
        # 2 Arguments, gets the url to add to the queue and the pattern to use
        # when checking pages.
        pattern = URI.join( opts[:crawl][0], opts[:crawl][1] ).to_s
        insert_data_into(@queue, [ opts[:crawl][0], opts[:crawl][1], 1, 0 ])
      else
        # No Arguments. Resume the crawler.
      end
    else
      Process.exit
    end

  end

  def create_config
    # Ask to create new config
    puts "No config file given, or exists. Would you like to create one? (y/n) "
    ans = $stdin.gets[0,1].chomp.downcase
    unless ans == 'y' then Process.exit end

    # Enter the base domain
    puts "Enter the base domain to be crawled. (ex: http://www.example.com) "
    domain = $stdin.gets.chomp.downcase
    if !domain.include?('http://') then domain = "http://#{ domain }" end

    while true
      # Get the shelf life, check to make sure it is an integer
      puts "Enter a shelf life(time between crawls) in hours. Default is 24 hours. "
      shelf = $stdin.gets.chomp
      if shelf == '' then shelf = "24" end
      if shelf.numeric? then break else puts "Please enter an integer." end
    end

    # Ask for database type
    puts "What type of database would you like to use?\nmysql or sqlite? "
    type = $stdin.gets.chomp.downcase

    # Ask for database name
    puts "Enter the name of your database: "
    db_name = $stdin.gets.chomp

    while true
      if type == 'mysql'
        puts "Username: "
        user = $stdin.gets.chomp
        puts "Password: "
        pass = $stdin.gets.chomp
        puts "Enter the Socket path\nExample: /Applications/MAMP/tmp/mysql/mysql.sock"
        sock = $stdin.gets.chomp
        break
      elsif type == 'sqlite'
        if db_name[-7,7] != ".sqlite" then db_name = "#{ db_name }.sqlite" end
        # Get DB path, and check if it is a valid path
        puts "Enter the absolute path for the database directory (leave blank for default)\nExample: #{ Dir.getwd }/data/ "
        db_path = "#{ $stdin.gets.chomp.downcase }"
        if db_path == '' then db_path = "#{ Dir.getwd }/data/" end
        if File.directory?("#{ db_path }")
          break
        else
          begin
            Dir.mkdir(db_path)
            break
          rescue SustemCallError
            puts "Please enter a valid path"
          end
        end
      else
        puts "Please enter either 'mysql' or 'sqlite'"
      end
    end

    # Enter the new config file name
    puts "Enter the name of your config file:\nExample: my_conf.yaml "
    config_name = $stdin.gets.chomp
    if config_name[-5,5] != ".yaml" then config_name = "#{ config_name }.yaml" end

    # Call create_db
    if type == "mysql"
      create_db(type, user, pass, sock, db_name)
    elsif type == "sqlite"
      create_db(type, nil, nil, nil, "#{ db_path }#{ db_name }")
    end

    # Create Config file
    config_file = File.open(config_name, 'w')
    config_file.puts("# Cosa config file\n\ndomain: #{ domain }\n\n# Amount of time between crawls on the same page\n# 86400 seconds by default (1 day)\nshelf_life: #{ shelf.to_i * 3600 }\n\n")

    if type == 'mysql'
      config_file.puts("# mysql db name, username, password and socket path\nname: #{ db_name }\nuser: #{ user }\npass: #{ pass }\nsock: #{ sock }")
    elsif type == 'sqlite'
      config_file.puts("# Ex) /Users/username/Documents/cosa/data/webcrawler.sqlite\ndb_path: #{ db_path }#{ db_name }")
    end
    config_file.puts("\n\n# Exceptions - directories Cosa should avoid when crawling\nexceptions:")

    config_file.close
    return config_name
  end


  def create_db(type, user, pass, sock, path)
    puts "creating db"
    if type == 'mysql'
      new_db = Sequel.connect(:adapter => 'mysql', :user => user, :socket => sock, :database => path, :password => pass)
    else
      new_db = Sequel.connect("sqlite://#{ path }")
    end

    new_db.create_table :queue do
      primary_key :id
      String :url
      String :pattern
      Integer :force
      Integer :in_use, :default => 0
    end
    new_db.create_table :urls do
      String :url, :text=>true
      String :accessed
      String :content_type
      Integer :content_length
      String :status
      String :response, :text=>true
      Float :response_time
      String :validation_type
      Integer :valid
    end
    new_db.create_table :links do
      String :from_url, :text=>true
      String :to_url, :text=>true
      String :type
    end
    new_db.disconnect
  end

end
