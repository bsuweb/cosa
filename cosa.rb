#!/usr/bin/env ruby
# encoding: utf-8

require 'nokogiri'
require 'typhoeus'
require 'sequel'
require 'uri'
require './lib/valid'
require './cli'
require './options'

class String
  def numeric?
    !self.match(/[^0-9]/)
  end

  def alpha?
    !self.match(/[^A-z]+$/)
  end
end

class Database

  def on_start
    to_crawl = queue.where(:in_use => 1)
    to_crawl.each { |item| queue.where(:id => item[:id]).update(:in_use => 0) }
  end

  # For each page in the urls table, see if the page has been
  # accessed within the seed time. If it has not,add that url to the
  # queue with the pattern set to '' and force set to 0.
  #
  def seed
    to_crawl = urls.where{ accessed < Time.now - @@SHELF }
    to_crawl.each { |row| insert_data_into_into(queue, [row[:url], '', 0]) }
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

    # If the current row is in use, get the next row that is not in use.
    if row[:in_use] == 1
      row = queue.where(:in_use => 0).limit(1).first
    end
    # Set the current row to in use
    queue.where(:id => row[:id]).update(:in_use => 1)

    # If the force column in the sequel object is set to true crawl the page.
    # Elsif the url of the sequel object is not in the urls table crawl the page.
    # Elsif the sequel object is in the urls table, but has not been accessed
    # within the shelf time crawl the page.
    if row[:force] == 1
      crawl_url(row[:id])
    elsif !urls[:url => row[:url]]
      crawl_url(row[:id])
    elsif urls[:url => row[:url]] && Time.now - Time.parse(urls.where(:url => row[:url]).get(:accessed)) > @@SHELF
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

    if url[-1, 10] == "index.html"
      url = url[0..-10]
    end

    response = Typhoeus::Request.get(url,
                                    :timeout => 30000,
                                    :followlocation => true,
                                    :maxredirs => 5,
                                    :headers => {
                                      'User-Agent' => "Cosa/0.2 ()"
                                    })
    url = response.effective_url
    url[0..4].downcase
    response_time = response.total_time.round(6)

    content_type = response.headers_hash["Content-Type"]
    if response.headers_hash["Content-Length"].to_s.numeric?
      content_length = response.headers_hash["Content-Length"]
    else
      content_length = ""
    end

    if content_type.include?(';')
      content_type = content_type[0..content_type.index(';')-1]
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

        # Iterate through the a, link, img, video, audio, script, and object elements on the page.
        Nokogiri::HTML(body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|
          if item.name == "link"
            if item.attr('rel') == "stylesheet"
              type = 'css'
            else
              type = ''
            end
          else
            type = item.name
          end

          # If element contains an href attribute, and that is not set to '#' or
          # 'mailto:', or http://, or contains a '@' symbol add that element to
          # the parsed_links array. Also add that element and it's 'tag' to the
          # type_array array.
          if item[:href]
            if !item[:href].nil? && !item[:href].include?('#') && !item[:href].include?('mailto:') && item[:href] != "http://" && !item[:href].include?('@')
              except_or_insert(URI.escape(item[:href].gsub(/\s+"|"/, '').strip, "[]()|% "), type, parsed_links, type_array, url)
            # Else if the element contains an scr attribute, add it to the
            # parsed_links array. Also add that element and it's 'tag' to the
            # type_array array.
            elsif item[:src] && item[:src][0..4] != 'data:'
              except_or_insert(URI.escape(item[:src].gsub(/\s+"|"/, '').strip, "[]()|% "), type, parsed_links, type_array, url)
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
            insert_data_into(links, [url, link, type])
          end
        else

          # Else the entry for the current url in the links table is not empty.
          # Add each of those links to the old_links array.
          links.where(:from_url => url).each { |link| old_links << link[:to_url] }
        end

        # Find the differences between old_links and parsed_links to determine if
        # any links have been added or removed from the page.
        if item[:force] == 1 then new_links = parsed_links else new_links = parsed_links - old_links end
        deleted_links = old_links - parsed_links
        deleted_links.each { |link| links.where(:to_url => link).delete }

        new_links = remove_leading(new_links)
        new_links.each do |link|
          type = determine_type(link, type_array)

          # If this item in the new_links array is not in the links table, add it
          # to the links table.
          unless links.where(:from_url => url, :to_url => link)
            insert_data_into(links, [url, link, type])
          end

          # If the current url's pattern field is blank, add this item from
          # new_links to the queue with a blank pattern and a force value of 0.
          if item[:pattern] == ''
            if check_duplicates(link) == true then insert_data_into(queue, [link, '', 0, 0]) end
          # Elsif the pattern is not blank and 'link' matches the pattern, add
          # link to the queue with the same pattern and force value.
          elsif item[:pattern] != '' && link.include?(item[:pattern])
            if check_duplicates(link) == true then insert_data_into(queue, [link, item[:pattern], item[:force], 0]) end
          end
        end
      end

      if url.include?('http') && !url.include?(domain)
        body = ''
      end

    else
      body = ''
    end

    rec = urls.where(:url => url)

    if output == "default"
      print "#{ queue_id }: #{ url } \n"
      print "Remaining: #{ queue.count } | Avg Req: #{ avg_response(response_time) }  | Total time: #{ (Time.now - start_time).round(2) }\r"
      $stdout.flush
    elsif output == "verbose"
      puts "QueueID: #{ queue_id }
      Current URL: #{ url }
      Last Accessed: #{ last_accessed }
      Content Type: #{ content_type }
      Status Code: #{ status }
      Page Reponse Time: #{ response_time }
      Total Time: #{ Time.now - start_time } \n
      #{ body.gsub(/[^a-zA-Z0-9\s\$\^<>=[:punct:]-]/, '') }"
    end

    if urls[:url => url]
      rec.update(:accessed => last_accessed, :response => body.gsub(/[^a-zA-Z0-9\s\$\^<>=[:punct:]-]/, ''))
    else
      insert_data_into(urls, [url, last_accessed, content_type, content_length, status, body.gsub(/[^a-zA-Z0-9\s\$\^<>=[:punct:]-]/, ''), response_time, valid[1], valid[0]])
    end

  end

  def except_or_insert(item, link_type, parsed_links, type_array, url)
    @exceptions.each do |dir|
      unless (URI.join(domain, item).to_s).include?(URI.join(domain, dir).to_s)
        begin
          insert_links(item, url, link_type, parsed_links, type_array)
        rescue URI::InvalidURIError
          insert_data_into(links, [url, item, 'broken'])
        end
      end
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
    queue_opts = [:url, :pattern, :force, :in_use]
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
  # type          - Link type (a, css, rss, img, script, video, audio, object)
  # parsed_links  - Array of links on the current url
  # type_array    - Array of links on the current page and their 'types'
  #
  def insert_links(item, url, type, parsed_links, type_array)
    item = URI.join(url, item).to_s
    parsed_links << item
    type_array << [item, type]
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
    if queue[:url => link] || link == domain + '/'
      false
    else
      dataset = urls.where(:url => link).limit(1)
      if dataset.empty?
        true
      elsif Time.parse(dataset.first[:accessed]) < (Time.now - @@SHELF)
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
    type[1]
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
      elsif link.include?("..")
        link.replace(URI.join( domain, link[link.index("..")+2..-1] ).to_s)
      end
      link
    end
    links_array
  end

  def avg_response(time)
    @crawled += 1
    @avg_response += time
    return (@avg_response / @crawled).round(3)
  end

end

crawler = Database.new(cli)
crawler.on_start

# Check the next item in the queue as long as the queue is not empty
while true
  if !crawler.queue.empty?
    crawler.crawl_queue
  else
    break
  end
end
