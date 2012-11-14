require 'rubygems'
require 'nokogiri'
require 'typhoeus'
require 'sequel'
require 'yaml'
require './lib/valid'

class Crawler
	attr_accessor :db, :bsu_urls, :bsu_links, :queue, :SHELF, :domain

	def initialize()
    # Load configuration file
    #config = YAML::load( File.open( 'config') )

		@db = Sequel.connect('sqlite:///Users/matt/Documents/crawler/data/webcrawler.db')
		@bsu_urls = db[:bsu_urls]
		@bsu_links = db[:bsu_links]
		@queue = db[:queue]
		@SHELF = 1#86400
    #temp
    @domain = "www.bemidjistate.edu"
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
	crawler.bsu_urls.each do |row|
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
  row = crawler.queue.first

  if row[:force] == true
    crawl_url(row[:id], crawler)
  elsif !crawler.bsu_urls[:url => row[:url]]
    crawl_url(row[:id], crawler)
  elsif crawler.bsu_urls[:url => row[:url]] && Time.now - Time.parse(crawler.bsu_urls.where(:url => row[:url]).get(:accessed)) > crawler.SHELF
    crawl_url(row[:id], crawler)
  end
  crawler.queue.where(:id => row[:id]).delete

end

def crawl_url(queue_id, crawler)

  item = crawler.queue[:id => queue_id]
  url = item[:url]
  last_accessed = Time.now
  parsed_links = []
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

      Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|
        if item[:href]
          if item[:href] != "#" && !item[:href].include?('mailto:')
            parsed_links << item[:href]
            type_array << item[:href]
          end
        elsif item[:src]
          parsed_links << item[:src]
          type_array << item[:src]
        end
      end

      #type_array.each { |array| array = removeLeading(array) }
      type_array = removeLeading(type_array)
      parsed_links = removeLeading(parsed_links)
      parsed_links.uniq!

      if crawler.bsu_links.where('from_url = ?', url).empty?

        parsed_links.each do |link|
          #type = determineType(link, type_array) type[1]
          insert_data(crawler, crawler.bsu_links, [url, link, 1])
        end

        old_links = []
      else
        old_links = []
        crawler.bsu_links.where('from_url = ?', url).each { |link| old_links << link[:to_url] }
      end

      new_links = parsed_links - old_links
      deleted_links = old_links - parsed_links

      deleted_links.each do |link|
        crawler.bsu_links.where('to_url = ?', link).delete
      end

      new_links = removeLeading(new_links)
      new_links.each do |link|
        #type = determineType(link, type_array) type[1]

        unless crawler.bsu_links.where(:from_url => url, :to_url => link)
          insert_data(crawler, crawler.bsu_links, [url, link, 1])
        end

        if item[:pattern] == ''
          unless crawler.queue[:url => link]
            insert_data(crawler, crawler.queue, [link, '', 0])
          end
        elsif item[:pattern] != '' && link == item[:pattern]
          insert_data(crawler, crawler.queue, [link, item[:pattern], item[:force]])
        end
      end
    end

    if internal == false
      body = ''
    end

  else
    body = ''
  end

  rec = crawler.bsu_urls.where(:url => url)

  puts "queue_id: #{ queue_id }
  item: #{ item }
  url: #{ url }
  last_accessed: #{ last_accessed }
  content type: #{ content_type }
  status: #{ status }"

  if crawler.bsu_urls[:url => url]
    rec.update(:accessed => last_accessed, :response => body)
  else
    insert_data(crawler, crawler.bsu_urls, [url, last_accessed, content_type, 1, status, body, valid[1], valid[0]])
  end


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
def removeLeading(links_array)
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

  if table == crawler.queue
    queue.each_with_index { |k,i| data_hash[k] = values[i]}
  elsif table == crawler.bsu_links
    links.each_with_index { |k,i| data_hash[k] = values[i]}
  elsif table == crawler.bsu_urls
    urls.each_with_index { |k,i| data_hash[k] = values[i]}
  end

  crawler.db.transaction do
    table.insert(data_hash)
  end
end

crawler = Crawler.new()
seed(crawler)

while true
  crawl_queue(crawler)

  if crawler.queue.empty?
    puts "queue empty"
    break
  end
end



