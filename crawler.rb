require 'rubygems'
require 'nokogiri'
require 'typhoeus'
require 'sequel'
require 'yaml'
require 'uri'
require './lib/valid'

class Crawler
	attr_accessor :db, :urls, :links, :queue, :SHELF, :domain

	def initialize()
    # Load configuration file
    # Used to load the base domain to be crawled, and the path to the database
    config = YAML::load( File.open( 'config.yaml') )

		@db = Sequel.connect(config['db_path'])
		@urls = db[:urls]
		@links = db[:links]
		@queue = db[:queue]
		@SHELF = 86400
    @domain = config['domain']
    # @domain = "http://" + config['domain'] unless @domain.include?("http://")
	end

  def set_args()
    #TODO
  end

end

#For each page in the urls table, see if the page has been
#accessed within the seed time. If it has not,add that url to the
#queue with the pattern set to '' and force set to 0.
#
# crawler - Crawler object
#
def seed(crawler)
	crawler.urls.each do |row|
		if Time.parse(row[:accessed]) < Time.now - crawler.SHELF
      insert_data(crawler, crawler.queue, [row[:url], '', 0])
		end
	end
  crawl_queue(crawler)
end

#Get the first row in the queue and check to see if either the force flag is
#on, or if the url has not been added to the urls table, or if it has been
#added to the urls table AND the url has not been accessed within the seed time
#
# crawler - Crawler object
#
def crawl_queue(crawler)
  # Create a Sequel object that corresponds to the first item in the queue
  # table. 'row' gets that value.
  row = crawler.queue.first

  # If the force column in the sequel object is set to true crawl the page.
  # Elsif the url of the sequel object is not in the urls table crawl the page.
  # Elsif the sequel object is in the urls table, but has not been accessed
  # within the shelf time crawl the page.
  if row[:force] == true
    crawl_url(row[:id], crawler)
  elsif !crawler.urls[:url => row[:url]]
    crawl_url(row[:id], crawler)
  elsif crawler.urls[:url => row[:url]] && Time.now - Time.parse(crawler.urls.where(:url => row[:url]).get(:accessed)) > crawler.SHELF
    crawl_url(row[:id], crawler)
  end
  # Delete the sequel object from the queue table.
  crawler.queue.where(:id => row[:id]).delete

  unless crawler.queue.empty?
    crawl_queue(crawler)
  end

end

def crawl_url(queue_id, crawler)

  item = crawler.queue[:id => queue_id]
  url = item[:url]
  last_accessed = Time.now
  parsed_links = []
  old_links = []
  type_array = []

  if url.include?(crawler.domain)
    #url is internal, url = url
  elsif url[0] == '/' || url[0,2] == '../'
    #url is internal
    url = crawler.domain + url
  elsif url.include?('http')
    #url is external, url = url
    internal = false
  else
    url = crawler.domain + '/' + url
  end

  response = Typhoeus::Request.get(url, :timeout => 30000)

  content_type = response.headers_hash["Content-Type"]
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
    if url.include?(crawler.domain)

      # Iterate through the a, link, img, video, audio, script, and object elements on the page.
      Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|

        # If element contains an href attribute, and that is not set to '#' or
        # 'mailto:', add that element to the parsed_links array. Also add that
        # element and it's 'tag' to the type_array array.
        if item[:href]
          if item[:href] != "#" && !item[:href].include?('mailto:')
            parsed_links << item[:href]
            type_array << [item[:href], item.name]
          end

        # Else if the element contains an scr attribute, add it to the
        # parsed_links array. Also add that element and it's 'tag' to the
        # type_array array.
        elsif item[:src]
          parsed_links << item[:src]
          type_array << [item[:src], item.name]
        end
      end

      type_array.each { |array| array = remove_leading(array) }
      parsed_links = remove_leading(parsed_links)
      parsed_links.uniq!

      # If the entry for the current url in the links table is empty, add each
      # item from the parsed_links array to the links table with the format
      # :from_url => current_url, :to_url => parsed_links_item, :type => type
      if crawler.links.where('from_url = ?', url).empty?

        parsed_links.each do |link|
          type = determine_type(link, type_array)
          insert_data(crawler, crawler.links, [url, link, type[1]])
        end

        # Create old_links array. Since this page had no links in the table
        # previously, the old_links array is empty.
      else

        # Else the entry for the current url in the links table is not empty.
        # Add each of those links to the old_links array.
        crawler.links.where('from_url = ?', url).each { |link| old_links << link[:to_url] }
      end

      # Find the differences between old_links and parsed_links to determine if
      # any links have been added or removed from the page.
      new_links = parsed_links - old_links
      deleted_links = old_links - parsed_links

      deleted_links.each do |link|
        crawler.links.where('to_url = ?', link).delete
      end

      new_links = remove_leading(new_links)
      new_links.each do |link|
      type = determine_type(link, type_array)

        # If this item in the new_links array is not in the links table, add it
        # to the links table. MAY BE REDUNDANT
        unless crawler.links.where(:from_url => url, :to_url => link)
          insert_data(crawler, crawler.links, [url, link, type[1]])
        end

        # If the current url's pattern field is blank, add this item from
        # new_links to the queue with a blank pattern and a force value of 0.
        if item[:pattern] == ''
          unless crawler.queue[:url => link]
            dataset = crawler.urls[:url => link]
            if dataset.nil?
              insert = true
            elsif Time.parse(dataset[:accessed]) < (Time.now - crawler.SHELF)
              insert = true
            else
              insert = false
            end

            insert_data(crawler, crawler.queue, [link, '', 0]) if insert == true
          end

          # if !crawler.queue.where(:url => link) || crawler.url.where(:url => link) & (:accessed > Time.now - crawler.SHELF)

        # Elsif the pattern is not blank and 'link' matches the pattern, add
        # link to the queue with the same pattern and force value.
        elsif item[:pattern] != ''
          unless crawler.queue[:url => link]
            dataset = crawler.urls[:url => link]
            if dataset.nil?
              insert = true
            elsif Time.parse(dataset[:accessed]) < (Time.now - crawler.SHELF)
              insert = true
            else
              insert = false
            end
            insert_data(crawler, crawler.queue, [link, item[:pattern], item[:force]]) if insert == true
          end
        end
      end
    end

    if internal == false
      body = ''
    end

  else
    body = ''
  end

  rec = crawler.urls.where(:url => url)

  puts "queue_id: #{ queue_id }
  item: #{ item }
  url: #{ url }
  last_accessed: #{ last_accessed }
  content type: #{ content_type }
  status: #{ status }"

  if crawler.urls[:url => url]
    rec.update(:accessed => last_accessed, :response => body)
  else
    insert_data(crawler, crawler.urls, [url, last_accessed, content_type, 1, status, body, valid[1], valid[0]])
  end


end

#Determines the type of a link based on its 'tag'
#
# link - The link to be tested
# type_array - Array with the links, and their tag
#
def determine_type(link, type_array)
  type = type_array.assoc(link)
  type[1] = 'css' if type[1] === 'link'
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
# crawler - Crawler object
# table   - Table to insert data
# values   - Values to be inserted into table
#
def insert_data(crawler, table, values)
  queue = [:url, :pattern, :force]
  links = [:from_url, :to_url, :type]
  urls = [:url, :accessed, :content_type, :content_length, :status, :response, :validation_type, :valid]

  data_hash = {}

  # Checks to see which table is being accessed and then creates the hash to
  # added to the table. Does this by taking the first item from the table
  # array(queue, links, or urls) and sets it as the key in the data_hash
  # Hash object. That key is given the value of values[i]. i, and k are
  # incremented and the process repeats itself.
  if table == crawler.queue
    queue.each_with_index { |k,i| data_hash[k] = values[i] }
  elsif table == crawler.links
    links.each_with_index { |k,i| data_hash[k] = values[i] }
  elsif table == crawler.urls
    urls.each_with_index { |k,i| data_hash[k] = values[i] }
  end

  crawler.db.transaction do
    table.insert(data_hash)
  end
end

crawler = Crawler.new()
seed(crawler)
