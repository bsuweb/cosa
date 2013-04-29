require 'sequel'

class String
  def numeric?
    !self.match(/[^0-9]/)
  end

  def alpha?
    !self.match(/[^A-z]+$/)
  end
end

# Load configuration file, configure Cosa
module Configure
  def config(config, init)
    # FIX THIS
    @config = get_config(config, init)
    if File.exists?('config.yaml')
      @config ||= YAML::load(File.open('config.yaml'))
    else
      @config ||= YAML::load(File.open(create_config))
    end

    if @config['db_path']
      if File.exists?(@config['db_path'])
        @db = Sequel.connect("sqlite://#{ @config['db_path']}")
      else
        puts "The database listed in your config file does not exist. Would you like to create it? (y/n)"
        ans = $stdin.gets[0,1].chomp.downcase
        unless ans == 'y' then Process.exit end
        create_db('sqlite', nil, nil, nil, "#{@config['db_path']}")
        @db = Sequel.connect("sqlite://#{ @config['db_path'] }")
      end
    else
      @db = Sequel.connect(:adapter => 'mysql',
                          :user => config['user'],
                          :socket => config['sock'],
                          :database => config['name'],
                          :password => config['pass'])
    end

    shelf = @config['shelf']
    shelf ||= 86400
    return {
            "db"   => @db,
            "urls" => @db[:urls],
            "links" => @db[:links],
            "queue" => @db[:queue],
            "domain" => @config['domain'],
            "exceptions" => @config ['exceptions'],
            "shelf" => shelf
           }

  end

  def get_config(config, init)
    if config
      if File.exists?(config)
        return YAML::load(File.open(config))
      else
        return YAML::load(File.open(create_config))
      end
    elsif init
      return YAML::load(File.open(create_config))
    else
      return nil
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
      shelf = "24" if shelf.empty?
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
    puts "Creating Database..."
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
