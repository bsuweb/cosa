require 'nokogiri'
require 'typhoeus'
require 'sequel'
require 'yaml'
require 'uri'
require 'trollop'
require './lib/valid'

class String
  def numeric?
    !self.match(/[^0-9]/)
  end
end

class Database
  attr_accessor :opts, :db, :urls, :links, :queue, :SHELF, :domain, :start_time, :output

  def initialize
    opts = Trollop::options do
      version " Cosa 0.1"
      banner <<-EOS
      Cosa is a simple web crawler that generates a database for use by other
      tools and reports.

      Usage:
        ruby cosa.rb http://www.example.com [-options]
          - Cosa will start at this address, and crawl every page on the site.

        ruby cosa.rb http://www.example.com/directory/ /directory/page/ [-options]
          - Cosa will start at 'http://www.example.com/directory/', and then
            only add links to the queue if they contain the pattern
            'http://www.example.com/directory/page'.

        ruby cosa.rb [-options]
          - If you have already run Cosa, this will check the first link in the
            urls table and see if it has been crawled within the shelf time
            (default 1 day). If it hasn't, that URL will be added to the
            queue and the URL will be recrawled.

        Because Cosa stores the queue in the database, you can quit the program
        at any time and when you restart it, it will begin where it left off.
      EOS

      opt :init, "Command-line tool for creating and saving a config file"
      opt :add, "Add a URL to the queue", :type => :strings
      opt :config, "If not specified, Cosa will use the default config if it exists", :type => :string
      opt :crawl, "Start the crawler. Optional switches for silent or verbose output.", :type => :strings
      opt :broken, "List all URLs that contain broken links and their broken links."
      opt :abandoned, "List all pages that are no longers linked to."
      opt :invalid_html, "List pages with invalid html."
      opt :css, "List all CSS URLs that are linked to."
      opt :age, "List all URLs that are older than the given date.", :type => :string
      opt :queue, "List the current queue."
      opt :clear_queue, "Empty the queue"
      opt :response_time, "List the URLs that took longer than <seconds> to respond.", :type => :float, :short => '-r'
      opt :unresponsive, "List URLs that were not responsive."
      opt :to, "List URLs that link to the given URL.", :type => :string
      opt :from, "List URLs that the given URL links to.", :type => :string
      opt :silent, "Silence all output.", :short => 's'
      opt :snapshot, "Export the entire site from cosa as an HTML snapshot to the given path.", :type => :string, :short => "-o"
      opt :verbose, "Verbose output.", :short => "-v"
    end
  set_opts(opts)
  end

  def set_opts(opts)
    # Load configuration file
    # Used to load the base domain to be crawled, and the path to the database
    if opts[:config]
      config = YAML::load( File.open(opts[:config]) )
    elsif File.exists?('config.yaml')
        config = YAML::load( File.open('config.yaml') )
    else
      # create_config
    end

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
    end

  end

  def create_config
    strings = [
              "No config file given, or exists. Would you like to create one? (y/n) ",
              "Enter the base domain to be crawled. (ex: http://www.example.com) ",
              "Enter a shelf life(time between crawls) in hours. Default is 24 hours. ",
              "Enter a path for the database (leave blank for default) "
              ]

    puts strings[0]
    ans = $stdin.gets[0,1].chomp.downcase
    if ans == 'y'
      puts strings[1]
      domain = $stdin.gets.chomp.downcase
      puts strings[2]
      shelf = $sdtin.gets.chomp
      puts strings[3]
      db_path = $sdtin.gets.chomp.downcase
    end
  end

  # For each page in the urls table, see if the page has been
  # accessed within the seed time. If it has not,add that url to the
  # queue with the pattern set to '' and force set to 0.
  #
  def seed
    to_crawl = urls.where{ accessed < Time.now - @@SHELF }
    to_crawl.each do |row|
      insert_data_into_into(queue, [row[:url], '', 0])
    end

    return crawl_queue unless queue.empty?
  end

  # Get the first row in the queue and check to see if either the force flag is
  # on, or if the url has not been added to the urls table, or if it has been
  # added to the urls table AND the url has not been accessed within the seed
  # time
  #
  def crawl_queue
    # Get the first item in the queue table. Variable 'row' gets that value.
    row = queue.first

    # If the force column in the sequel object is set to true crawl the page.
    # Elsif the url of the sequel object is not in the urls table crawl the page.
    # Elsif the sequel object is in the urls table, but has not been accessed
    # within the shelf time crawl the page.
    if row[:force] == 1
      crawl_url(row[:id])
    elsif !urls[:url => row[:url]]
      crawl_url(row[:id])
    elsif urls[:url => row[:url]] && Time.now - Time.parse(urls.where(:url => row[:url]).get(:accessed)) > SHELF
      crawl_url(row[:id])
    end
    # Delete the sequel object from the queue table.
    queue.where(:id => row[:id]).delete
  end

  def crawl_url(queue_id)

    item = queue[:id => queue_id]
    url = item[:url]
    last_accessed = Time.now
    parsed_links = []
    old_links = []
    type_array = []

    if url.include?('http') && !url.include?(domain)
      #url is external, url = url
      internal = false
    elsif url[-1, 10] == "index.html"
      url = url[0..-10]
    end

    response = Typhoeus::Request.get(url,
                                    :timeout => 30000,
                                    :headers => {
                                      'User-Agent' => "Cosa/0.1 ()"
                                    })
    url = response.effective_url
    response_time = response.total_time.round(6)

    content_type = response.headers_hash["Content-Type"]
    if response.headers_hash["Content-Length"].to_s.numeric?
      content_length = response.headers_hash["Content-Length"]
    else
      content_length = ""
    end

    if content_type.include?(';')
      content_type = content_type[0, content_type.index(';')]
    elsif content_type == {}
      content_type = ""
    end

    status = response.code
    body = response.body
    if status == 404
      valid = [0, 0]
    else
      valid = valid?(url, content_type)
      #valid = [1, 1]
    end

    if valid[1] == "html"
      if url.include?(domain)

        # Iterate through the a, link, img, video, audio, script, and object elements on the page.
        Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|

          # If element contains an href attribute, and that is not set to '#' or
          # 'mailto:', or http://, or contains a '@' symbol add that element to
          # the parsed_links array. Also add that element and it's 'tag' to the
          # type_array array.
          if item[:href]
            if !item[:href].include?('#') && !item[:href].include?('mailto:') && item[:href] != "http://" && !item[:href].include?('@')
              insert_links(item, url, :href, parsed_links, type_array)
            end
          # Else if the element contains an scr attribute, add it to the
          # parsed_links array. Also add that element and it's 'tag' to the
          # type_array array.
          elsif item[:src]
            if item[:src][0..4] != 'data:'
              insert_links(item, url, :src, parsed_links, type_array)
            end
          end
        end

        type_array.each { |array| array = remove_leading(array) }
        parsed_links = remove_leading(parsed_links)
        parsed_links.uniq!

        # If the entry for the current url in the links table is empty, add each
        # item from the parsed_links array to the links table with the format
        # :from_url => current_url, :to_url => parsed_links_item, :type => type
        if links.where(:from_url => url).empty?

          parsed_links.each do |link|
            type = determine_type(link, type_array)
            insert_data_into(links, [url, link, type[1]])
          end
        else

          # Else the entry for the current url in the links table is not empty.
          # Add each of those links to the old_links array.
          links.where(:from_url => url).each { |link| old_links << link[:to_url] }
        end

        # Find the differences between old_links and parsed_links to determine if
        # any links have been added or removed from the page.
        new_links = parsed_links - old_links
        deleted_links = old_links - parsed_links

        new_links = parsed_links if item[:force] == 1

        deleted_links.each do |link|
          links.where(:to_url => link).delete
        end

        new_links = remove_leading(new_links)
        new_links.each do |link|
        type = determine_type(link, type_array)

          # If this item in the new_links array is not in the links table, add it
          # to the links table.
          unless links.where(:from_url => url, :to_url => link)
            insert_data_into(links, [url, link, type[1]])
          end

          # If the current url's pattern field is blank, add this item from
          # new_links to the queue with a blank pattern and a force value of 0.
          if item[:pattern] == ''
            insert_data_into(queue, [link, '', 0]) if check_duplicates(link) == true

          # Elsif the pattern is not blank and 'link' matches the pattern, add
          # link to the queue with the same pattern and force value.
          elsif item[:pattern] != '' && link.include?(item[:pattern])
            insert_data_into(queue, [link, item[:pattern], item[:force]]) if check_duplicates(link) == true
          end
        end
      end

      if internal == false
        body = ''
      end

    else
      body = ''
    end

    rec = urls.where(:url => url)

    if output == "default"
      print "\rURL: #{ url } | Queue: #{ queue_id } | Avg Req: 1 | Total: #{ Time.now - start_time } DONE"
      $stdout.flush
    elsif output == "verbose"
      puts "QueueID: #{ queue_id }
      Current URL: #{ url }
      Last Accessed: #{ last_accessed }
      Content Type: #{ content_type }
      Status Code: #{ status }
      Page Reponse Time: #{ response_time }
      Total Time: #{ Time.now - start_time } \n"
    end

    if urls[:url => url]
      rec.update(:accessed => last_accessed, :response => body)
    else
      insert_data_into(urls, [url, last_accessed, content_type, content_length, status, body, response_time, valid[1], valid[0]])
    end

  end

  # Combines the array of given 'values' with an array of 'keys' based on the
  # table you wish to insert data to. The key and value arrays are combined
  # into a hash object and the data is inserted into the correct table.
  #
  # table    - Table to insert data
  # values   - Values to be inserted into table
  #
  def insert_data_into(table, values)
    queue_opts = [:url, :pattern, :force]
    links_opts = [:from_url, :to_url, :type]
    urls_opts = [:url, :accessed, :content_type, :content_length, :status, :response, :response_time, :validation_type, :valid]
    data_hash = {}

    # Checks to see which table is being accessed and then creates the hash to
    # added to the table. Does this by taking the first item from the table
    # array(queue, links, or urls) and sets it as the key in the data_hash
    # Hash object. That key is given the value of values[i]. i, and k are
    # incremented and the process repeats itself.
    if table == queue
      queue_opts.each_with_index { |k,i| data_hash[k] = values[i] }
    elsif table == links
      links_opts.each_with_index { |k,i| data_hash[k] = values[i] }
    elsif table == urls
      urls_opts.each_with_index { |k,i| data_hash[k] = values[i] }
    end

    db.transaction do
      table.insert(data_hash)
    end
  end

  # Edits links being added to parsed_links and type_array so that they are not
  # added as 'relative links'.
  #
  # item          - Curent page being added
  # url           - Current url
  # type          - href or src
  # parsed_links  - array of links on the current url
  # type_array    - array of links on the current page and their 'types'
  #
  def insert_links(item, url, type, parsed_links, type_array)
    item[type] = URI.join( url, URI.escape(item[type].gsub(/\s+\"|"/, '').strip, "[]()| ") ).to_s
    parsed_links << item[type]
    type_array << [item[type], item.name]
  end

  # Additional checking to make sure duplicate links aren't added to the queue.
  # Unless the current link is already in the queue, check to see if the
  # current link is listed in the urls table. If it isn't, return true. If it
  # is, and it hasn't been accessed in the last day return true. Else return
  # false. If true is returned, add the link to the queue.
  #
  # link    - Link being checked
  #
  def check_duplicates(link)
    unless queue[:url => link] || link == domain + '/'
      dataset = urls[:url => link]
      if dataset.nil?
        true
      elsif Time.parse(dataset[:accessed]) < (Time.now - @@SHELF)
        true
      else
        false
      end
    end
  end

  # Determines the type of a link based on its 'tag'
  #
  # link       - The link to be tested
  # type_array - Array with the links, and their tag
  #
  def determine_type(link, type_array)
    type = type_array.assoc(link)
    begin
      type[1] = 'css' if type[1] === 'link'
    rescue
      type = ['','']
    end
    type
  end

  # Removes the leading '/' or '../' from the links in an array
  #
  # links_array - The original array of links
  #
  # Example
  #
  #   removeLeading(['/page1.html', '../page2.html', 'page3.html'])
  #   # => ['page1.html', 'page2.html', 'page3.html']
  #
  def remove_leading(links_array)
    links_array.each do |link|
      if link[0] === '/'
        link.replace(link[1,link.length])
      elsif link[0..2] === '../'
        link.replace(link[3, link.length])
      end
    end
    links_array
  end

end

crawler = Database.new()

# if ARGV.length < 1
#   # No Arguments, check each url in the urls table and add old urls to the
#   # queue to be checked again.
#   # crawler.seed
#   Process.exit
# elsif ARGV.length > 1
#   # 2 Arguments, gets the url to add to the queue and the pattern to use when
#   # checking pages.
#   options = { :url => ARGV.shift, :pattern => ARGV.shift }
#   options[:pattern] = URI.join( options[:url], options[:pattern] ).to_s
#   crawler.insert_data_into(crawler.queue, [ options[:url], options[:pattern], 1 ])
# else
#   # 1 Argument, gets the url to add to the queue.
#   options = { :url => ARGV.shift, :pattern => ARGV.shift }
#   crawler.insert_data_into(crawler.queue, [ options[:url], '', 1 ])
# end

# Check the next item in the queue as long as the queue is not empty
while true
  if !crawler.queue.empty?
    crawler.crawl_queue
  else
    break
  end
end
