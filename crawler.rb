require 'rubygems'
require 'nokogiri'
require 'typhoeus'
require 'sequel'
require './lib/valid'

# Public: For each row in crawler_<site>_urls, see if the row has been
# accessed within the seed time. If it has not, add that url to the queue with
# the pattern set to '' and force set to 0.
#
# bsu_urls  - crawler_bsu_urls table
# queue     - crawler_queue table
# shelf     - Alias for SHELF_LIFE constant
#
def seed(bsu_urls, queue, shelf, options={})
  defaults = {
    domain: "www.bemidjistate.edu/",
    start_path: '/',
    pattern: '',
    force: 0
  }
  options = defaults.merge(options)

  bsu_urls.each do |row|
    if Time.parse(row[:accessed]) < Time.now - shelf || options[:force].to_i == 1
      puts "adding to queue"
      DB.transaction do #BEGIN
        queue.insert(:url => row[:url], :pattern => '', :force => options[:force]) #INSERT
      end #COMMIT
    end
  end
  crawl(bsu_urls, queue, shelf)
end


# Public: For each row in crawler_queue, check to see if the force option is
# on. If it is, crawl the url. Else if the url has not been crawled, crawl it.
# Else if the url has been crawled AND Time.now - Time last accessed is > the
# SHELF_TIME crawl the url. Then remove the row/url from the queue.
#
# bsu_urls  - crawler_bsu_urls table
# queue     - crawler_queue table
# shelf     - Alias for the SHELF_LIFE constant
#
def crawl(bsu_urls, queue, shelf)

  #Need to test this more
  queue.all.each do |row|
  puts row

    if row[:force] == true
      crawlUrl(row[:id], bsu_urls, queue)
    elsif !bsu_urls[:url => row[:url]]
      crawlUrl(row[:id], bsu_urls, queue)
    #Rewrite this so its more readable
    elsif bsu_urls[:url => row[:url]] && Time.now - Time.parse(bsu_urls.where(:url => row[:url]).get(:accessed)) > shelf
      crawlUrl(row[:id], bsu_urls, queue)
    end

    queue.where(:id => row[:id]).delete

  end
end


# Public: Get an item from the queue(queue_id) and store/update the url,
# accessed, content-type, content-length, etag, status, response, validation-
# type, and valid in the database.
#
# If the validation type is HTML, get all rows in the links table where the url
# == the current url, and set parsed_links to all of the links in the body of
# the page. For each difference(deleted links) between old_links and
# parsed_links, remove link from the links table. For each difference(new links
# )between old_links and parsed_links add link to links table. If the link is
# not in the urls table, if item.pattern = NULL then add it to the queue, else
# if item.patter !NULL && link matches item.pattern add it to the queue using
# same pattern and force values.
#
# queue_id - The id of the page to be crawled
# bsu_urls - crawler_bsu_urls table
# queue    - crawler_queue table
#
def crawlUrl(queue_id, bsu_urls, queue)
  db = Sequel.connect('sqlite:///Users/matt/Documents/crawler/data/webcrawler.db')

  bsu_links = db[:bsu_links]

  item = queue[:id => queue_id]
  url = item[:url]
  last_accessed = Time.now
  parsed_links = []
  type_array = []
  etag = ''
  #temp
  domain = "www.bemidjistate.edu"

  if url.include?(domain)
    #url is internal, url = url..
  elsif url[0] == '/' || url[0,2] == '../'
    #url is internal
    url = domain + url
  elsif url.include?('http')
    #url is external, url = url
    internal = false
  else
    url = domain + '/' + url
  end


  response = Typhoeus::Request.get(url, :timeout => 5000)

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
    # valid = [1, 1]
  end

  if valid[1] == "html"
    if url.include?(domain)

      Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|
        #Ugly, rewrite
        if !item[:href].nil? && item[:href]
          if item[:href] != "#" && !item[:href].include?('mailto:')
            parsed_links << item[:href]
            type_array << [item[:href], item.name]
          end
        elsif !item[:src].nil? && item[:src]
          parsed_links << item[:src]
          type_array << [item[:src], item.name]
        end
      end

      type_array.each { |array| array = removeLeading(array) }
      parsed_links = removeLeading(parsed_links)
      parsed_links.uniq!

      if bsu_links.where('from_url = ?', url).empty?

        parsed_links.each do |link|
          puts link
          # type = determineType(link, type_array) type[1]
          bsu_links.insert(:from_url => url, :to_url => link, :type => 1) #INSERT
        end

        old_links = []
      else
        old_links = []
        bsu_links.where('from_url = ?', url).each { |link| old_links << link[:to_url] }
      end

      new_links = parsed_links - old_links
      deleted_links = old_links - parsed_links

      deleted_links.each do |link|
        bsu_links.where('to_url = ?', link).delete
      end

      new_links = removeLeading(new_links)
      DB.transaction do #BEGIN
        new_links.each do |link|
          # type = determineType(link, type_array) type[1]

          unless bsu_links.where(:from_url => url, :to_url => link)
            bsu_links.insert(:from_url => url, :to_url => link, :type => 1)
          end

            if item[:pattern] == ''
              unless queue[:url => link]
                queue.insert(:url => link, :pattern => '', :force => 0) #INSERT
              end
            elsif item[:pattern] != '' && link == item[:pattern]
              queue.insert(:url => link, :pattern => item[:pattern], :force => item[:force]) #INSERT
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

  rec = bsu_urls.where(:url => url)

  puts "queue_id: #{ queue_id }
  item: #{ item }
  url: #{ url }
  last accessed: #{ last_accessed }
  content type: #{ content_type }
  status: #{ status }"

    if bsu_urls[:url => url]
      rec.update(:accessed => last_accessed, :response => body) #UPDATE
    else
      bsu_urls.insert([url, last_accessed, content_type, 1, status, body, valid[1], valid[0]]) #INSERT
  end


end

# Public: Determines the type of a link based on its HTML tag.
#
# link - The link to be tested
# type_array - Array with the links, and their tag
#
def determineType(link, type_array)
  type = type_array.assoc(link)
  type[1] = 'css' if type[1] === 'link'
  return type[1]
end

# Public: Removes the leading '/' or '../' from links in an array
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

#Database Connection
# DB = Sequel.sqlite('data/webcrawler.db')
# DB = Sequel.connect('sqlite://data/webcrawler.db')
DB = Sequel.connect('sqlite:///Users/matt/Documents/crawler/data/webcrawler.db')
queue = DB[:queue]
bsu_urls = DB[:bsu_urls]

if ARGV[0] == nil
  options = {}
else
  options = { domain: ARGV.shift, start_path: ARGV.shift, pattern: ARGV.shift, force: ARGV.shift }
end


#1 Day
SHELF_LIFE = 1#86400

while true
  puts "call seed"
  seed(bsu_urls, queue, SHELF_LIFE, options)

  if queue.empty?
    puts "queue empty"
    break
  end
end