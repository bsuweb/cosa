require 'rubygems'
require 'nokogiri'
require 'typhoeus'
require 'sequel'
require 'yaml'
require 'uri'
require './lib/valid'

class Cosa
	attr_accessor :db, :urls, :links, :queue, :SHELF, :domain, :start_time

	def initialize()
    # Load configuration file
    # Used to load the base domain to be crawled, and the path to the database
    config = YAML::load( File.open( 'config.yaml') )

		@db = Sequel.connect(config['db_path'])
		@urls = db[:urls]
		@links = db[:links]
		@queue = db[:queue]
    @domain = config['domain']
    @start_time = Time.now

    if config['shelf_life']
      @SHELF = config['shelf_life']
    else
      @SHELF = 86400
    end
	end

end

class String
  def numeric?
    !self.match(/[^0-9]/)
  end
end

#For each page in the urls table, see if the page has been
#accessed within the seed time. If it has not,add that url to the
#queue with the pattern set to '' and force set to 0.
#
# cosa - Cosa object
#
def seed(cosa)
  to_crawl = cosa.urls.where{accessed < Time.now - cosa.SHELF}
  to_crawl.each do |row|
    insert_data(cosa, cosa.queue, [row[:url], '', 0])
  end

  return crawl_queue(cosa) unless cosa.queue.empty?
end

#Get the first row in the queue and check to see if either the force flag is
#on, or if the url has not been added to the urls table, or if it has been
#added to the urls table AND the url has not been accessed within the seed time
#
# cosa - Cosa object
#
def crawl_queue(cosa)
  # Create a Sequel object that corresponds to the first item in the queue
  # table. 'row' gets that value.
  row = cosa.queue.first
  puts row

  # If the force column in the sequel object is set to true crawl the page.
  # Elsif the url of the sequel object is not in the urls table crawl the page.
  # Elsif the sequel object is in the urls table, but has not been accessed
  # within the shelf time crawl the page.
  if row[:force] == 1
    crawl_url(row[:id], cosa)
  elsif !cosa.urls[:url => row[:url]]
    crawl_url(row[:id], cosa)
  elsif cosa.urls[:url => row[:url]] && Time.now - Time.parse(cosa.urls.where(:url => row[:url]).get(:accessed)) > cosa.SHELF
    crawl_url(row[:id], cosa)
  end
  # Delete the sequel object from the queue table.
  cosa.queue.where(:id => row[:id]).delete
end

def crawl_url(queue_id, cosa)

  item = cosa.queue[:id => queue_id]
  url = item[:url]
  last_accessed = Time.now
  parsed_links = []
  old_links = []
  type_array = []

  if url.include?('http') && !url.include?(cosa.domain)
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
    if url.include?(cosa.domain)

      # Iterate through the a, link, img, video, audio, script, and object elements on the page.
      Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|

        # If element contains an href attribute, and that is not set to '#' or
        # 'mailto:', or http://, or contains a '@' symbol add that element to
        # the parsed_links array. Also add that element and it's 'tag' to the
        # type_array array.
        if item[:href]
          if !item[:href].include?('#') && !item[:href].include?('mailto:') && item[:href] != "http://" && !item[:href].include?('@')
            insert_links(cosa, item, url, :href, parsed_links, type_array)
          end
        # Else if the element contains an scr attribute, add it to the
        # parsed_links array. Also add that element and it's 'tag' to the
        # type_array array.
        elsif item[:src]
          if item[:src][0..4] != 'data:'
            insert_links(cosa, item, url, :src, parsed_links, type_array)
          end
        end
      end

      type_array.each { |array| array = remove_leading(array) }
      parsed_links = remove_leading(parsed_links)
      parsed_links.uniq!

      # If the entry for the current url in the links table is empty, add each
      # item from the parsed_links array to the links table with the format
      # :from_url => current_url, :to_url => parsed_links_item, :type => type
      if cosa.links.where(:from_url => url).empty?

        parsed_links.each do |link|
          type = determine_type(link, type_array)
          insert_data(cosa, cosa.links, [url, link, type[1]])
        end
      else

        # Else the entry for the current url in the links table is not empty.
        # Add each of those links to the old_links array.
        cosa.links.where(:from_url => url).each { |link| old_links << link[:to_url] }
      end

      # Find the differences between old_links and parsed_links to determine if
      # any links have been added or removed from the page.
      new_links = parsed_links - old_links
      deleted_links = old_links - parsed_links

      deleted_links.each do |link|
        cosa.links.where(:to_url => link).delete
      end

      new_links = remove_leading(new_links)
      new_links.each do |link|
      type = determine_type(link, type_array)

        # If this item in the new_links array is not in the links table, add it
        # to the links table.
        unless cosa.links.where(:from_url => url, :to_url => link)
          insert_data(cosa, cosa.links, [url, link, type[1]])
        end

        # If the current url's pattern field is blank, add this item from
        # new_links to the queue with a blank pattern and a force value of 0.
        if item[:pattern] == ''
          insert_data(cosa, cosa.queue, [link, '', 0]) if check_duplicates(cosa, link) == true

        # Elsif the pattern is not blank and 'link' matches the pattern, add
        # link to the queue with the same pattern and force value.
        elsif item[:pattern] != '' && link.include?(item[:pattern])
          insert_data(cosa, cosa.queue, [link, item[:pattern], item[:force]]) if check_duplicates(cosa, link) == true
        end
      end
    end

    if internal == false
      body = ''
    end

  else
    body = ''
  end

  rec = cosa.urls.where(:url => url)

  puts "queue_id: #{ queue_id }
  item: #{ item }
  url: #{ url }
  last_accessed: #{ last_accessed }
  content type: #{ content_type }
  content length: #{ content_length }
  status: #{ status }
  runtime: #{ Time.now - cosa.start_time}"

  if cosa.urls[:url => url]
    rec.update(:accessed => last_accessed, :response => body)
  else
    insert_data(cosa, cosa.urls, [url, last_accessed, content_type, content_length, status, body, valid[1], valid[0]])
  end

end

#Edits links being added to parsed_links and type_array so that they are not
#added as 'relative links'.
#
# cosa          - Cosa object
# item          - Curent page being added
# url           - Current url
# type          - href or src
# parsed_links  - array of links on the current url
# type_array    - array containing links on the current page and their 'types'
#
def insert_links(cosa, item, url, type, parsed_links, type_array)
  item[type] = URI.join( url, URI.escape(item[type].gsub(/\s+/, '').strip, "[]()| ") ).to_s
  parsed_links << item[type]
  type_array << [item[type], item.name]
end

#Additional checking to make sure duplicate links aren't added to the queue.
#Unless the current link is already in the queue, check to see if the current
#link is listed in the urls table. If it isn't, return true. If it is, and it
#hasn't been accessed in the last day return true. Else return false. If true
#is returned, add the link to the queue.
#
# cosa    - Cosa object
# link    - Link being checked
#
def check_duplicates(cosa, link)
  unless cosa.queue[:url => link] || link == cosa.domain + '/'
    dataset = cosa.urls[:url => link]
    if dataset.nil?
      return true
    elsif Time.parse(dataset[:accessed]) < (Time.now - cosa.SHELF)
      return true
    else
      return false
    end
  end
end

#Determines the type of a link based on its 'tag'
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
  return type
end

#Removes the leading '/' or '../' from the links in an array
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
  return links_array
end

#Combines the array of given 'values' with an array of 'keys' based on the
#table you wish to insert data to. The key and value arrays are combined into
#a hash object and the data is inserted into the correct table.
#
# cosa     - Cosa object
# table    - Table to insert data
# values   - Values to be inserted into table
#
def insert_data(cosa, table, values)
  queue = [:url, :pattern, :force]
  links = [:from_url, :to_url, :type]
  urls = [:url, :accessed, :content_type, :content_length, :status, :response, :validation_type, :valid]
  data_hash = {}

  # Checks to see which table is being accessed and then creates the hash to
  # added to the table. Does this by taking the first item from the table
  # array(queue, links, or urls) and sets it as the key in the data_hash
  # Hash object. That key is given the value of values[i]. i, and k are
  # incremented and the process repeats itself.
  if table == cosa.queue
    queue.each_with_index { |k,i| data_hash[k] = values[i] }
  elsif table == cosa.links
    links.each_with_index { |k,i| data_hash[k] = values[i] }
  elsif table == cosa.urls
    urls.each_with_index { |k,i| data_hash[k] = values[i] }
  end

  cosa.db.transaction do
    table.insert(data_hash)
  end
end

cosa = Cosa.new()

if ARGV.length < 1
  # No Arguments, check each url in the urls table and add old urls to the
  # queue to be checked again.
  seed(cosa)
elsif ARGV.length > 1
  # 2 Arguments, gets the url to add to the queue and the pattern to use when
  # checking pages.
  options = { "url" => ARGV.shift, "pattern" => ARGV.shift }
  options["pattern"] = URI.join( options["url"], options["pattern"] ).to_s
  insert_data(cosa, cosa.queue, [ options["url"], options["pattern"], 1 ])
else
  # 1 Argument, gets the url to add to the queue.
  options = { "url" => ARGV.shift, "pattern" => ARGV.shift }
  insert_data(cosa, cosa.queue, [ options["url"], '', 1 ])
end

# Check the next item in the queue as long as the queue is not empty
while true
  if !cosa.queue.empty?
    crawl_queue(cosa)
  else
    break
  end
end