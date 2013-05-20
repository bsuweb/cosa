# encoding: utf-8

require 'sequel'
require 'nokogiri'
require 'typhoeus'
require 'RMagick'
require 'uri'
require 'setup'
include Magick

class Cosa

  # Get the first row in the queue, and see if it is in use. If it is, get the next item.
  # Check to see if the current URLs force flag has been set, or if it has not been added
  # to the URLs table, or if it has been added to the URLs table AND the url has not been
  # accessed within the seed time. Then crawl that page.
  def crawl_queue
    row = queue.first
    if row[:in_use] == 1 then row = queue.where(:in_use => 0).limit(1).first end
    queue.where(:id => row[:id]).update(:in_use => 1)

    if row[:force] == 1
      crawl_url(row[:id])
    elsif !urls[:url => row[:url]]
      crawl_url(row[:id])
    elsif urls[:url => row[:url]] && Time.now - Time.parse(urls.where(:url => row[:url]).get(:accessed)) > @SHELF
      crawl_url(row[:id])
    end
    # Remove this item from the queue
    queue.where(:id => row[:id]).delete
  end

  def crawl_url(queue_id)
    # Get url from queue.
    i = queue[:id => queue_id]
    last_accessed = Time.now

    resp = Typhoeus::Request.get(i[:url], :timeout_ms => 30000,
                                :followlocation => true, :maxredirs => 5,
                                :headers => { 'User-Agent' => "Cosa/#{@@VERSION} ()" })

    # Get the effective url from Typhoeus, and convert the protocol to lowercase.
    url = resp.effective_url
    url[0..4].downcase

    body = resp.body
    response_time = resp.total_time.round(6)

    # If there was a redirection, insert the original url into the urls and links tables.
    if resp.redirect_count > 0
      insert_data_into(urls, [ i[:url], last_accessed, '', 0 , Typhoeus.get(i[:url]).code.to_s, '', 0, '', 0 ])
      insert_data_into(links, [ i[:url], url, "HTTP-Redirect" ])
    end

    begin
      content_type = resp.headers_hash["Content-Type"]
      if content_type.include?(';')
        content_type = content_type[0..content_type.index(';')-1]
      elsif content_type == {}
        content_type = ""
      end
      if resp.headers_hash["Content-Length"]
        content_length = resp.headers_hash["Content-Length"]
      else
        content_length = body.length
      end
    rescue NoMethodError
      content_type = "NA"
      content_length = "NA"
    end

    if resp.code == 404
      valid = [0,0]
    elsif resp.code == 0
      url = i[:url]
      valid = [0, valid(content_type)]
    else
      valid = [1, valid(content_type)]
    end

    if valid[1] == 'html' && url.include?(domain)
      type = ''
      parsed_links, old_links = {},{}
      links.where(:from_url => url).each { |link| old_links[link[:to_ur]] = link[:type] }
      Nokogiri::HTML(resp.body).css('a', 'link', 'img', 'video', 'audio', 'script', 'object').each do |item|
        if item.name == "link"
            if item.attr('rel') == "stylesheet"
              type = 'css'
            else
              type = ''
            end
        else
            type = item.name
        end

        if item[:href] && item[:href] !~ /#|@|mailto:|javascript:|file:/ && !item[:href].nil? && item[:href] != "http://"
          except_or_insert(URI.escape(item[:href].gsub(/\s+"|"/, '').strip, "[]()|%{} "), type, url, parsed_links)
        elsif item[:src] && !item[:src].include?('data:')
          except_or_insert(URI.escape(item[:src].gsub(/\s+"|"/, '').strip, "[]()|%{} "), type, url, parsed_links)
        end
      end

      parsed_links.each_pair do |k,v|
        if links.where(:from_url => k, :to_url => v)
          insert_data_into(links, [url, k, v])
        end

        if i[:pattern] == ''
          if check_duplicates(k) == true then insert_data_into(queue, [k, '', 0, 0]) end
        elsif i[:pattern] != '' && k.include?(i[:pattern])
          if check_duplicates(k) == true then insert_data_into(queue, [k, i[:pattern], i[:force], 0]) end
        end
      end
      deleted_links = old_links.to_a - parsed_links.to_a
      deleted_links.each { |link| links.where(:to_url => link[0]).delete }
    else
      body=''
    end

    rec = urls.where(:url => url)
    print_out(queue_id, url, last_accessed, content_type, resp.code, response_time, start_time)
    if urls[:url => url]
      rec.update(:accessed => last_accessed, :content_length => content_length, :response => body.gsub(/[^a-zA-Z0-9\s\$\^<>=[:punct:]-]/, ''))
    else
      insert_data_into(urls, [url, last_accessed, content_type, content_length, resp.code, body.gsub(/[^a-zA-Z0-9\s\$\^<>=[:punct:]-]/, ''), response_time, valid[1], valid[0]])
    end

    t = links.where(:to_url => url).limit(1)
    t.each { |x| t = x }
    if t[:type] == 'img' && (200..299).include?(resp.code)
      pic = ImageList.new(url)
      page = urls.where(:url => url).limit(1)
      page.each do |x|
        insert_data_into(meta, [ x[:id], "dimension-x", pic.columns ])
        insert_data_into(meta, [ x[:id], "dimension-y", pic.rows ])
        insert_data_into(meta, [ x[:id], "density", pic.density ])
      end
    end

  end

  def insert_data_into(table, values)
    queue_opts = [:url, :pattern, :force, :in_use]
    links_opts = [:from_url, :to_url, :type]
    urls_opts = [:url, :accessed, :content_type, :content_length, :status, :response, :response_time, :validation_type, :valid]
    meta_opts = [:id, :key, :value]
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
    elsif table == meta
      meta_opts.each_with_index { |k,i| data_hash[k] = values[i] }
    end

    db.transaction do
      table.insert(data_hash)
    end
  end

  def except_or_insert(item, type, url, parsed_links)
    begin
      # Combine the domain from the config file, and the passed item to form a URL.
      item = URI.join(domain, item).to_s
      # If item doesn't end with an extension and there is no trailing '/', add a '/' to the end
      if File.extname(item) == "" && item[-1,1] != '/' then item << '/' end
      # See if item matches any of the exceptions in the config file.
      unless @exceptions.nil?
        @exceptions.each do |reg|
          regex = Regexp.new(reg)
          unless item.match(regex)
            parsed_links[item] = type
          end
        end
      else
        parsed_links[item] = type
      end
    rescue URI::InvalidURIError
      insert_data_into(links, [url, item, 'broken'])
    rescue ArgumentError
      insert_data_into(links, [url, "ILL-FORMED LINK", 'broken'])
    end
  end

  def check_duplicates(link)
    if queue[:url => link] || link == domain + '/'
      false
    else
      dataset = urls.where(:url => link).limit(1)
      if dataset.empty?
        true
      elsif Time.parse(dataset.first[:accessed]) < (Time.now - @SHELF)
        true
      else
        false
      end
    end
  end

  def valid(content_type)
    content = content_type.to_s
    valid_array = [
                   {:html => "text/html"}, {:xml => "text/xml"},
                   {:css => "text/css"}, {:rss => "application/rss+xml"},
                   {:rss => "application/rdf+xml"}, {:rss => "application/atom+xml"},
                  ]
    valid_hash = Hash.new { |h, k| h[k] = [] }
    valid_array.each do |entry|
      entry.each_pair { |k, v| valid_hash[k] << v }
    end
    if valid_hash.has_value?([content])
      type = valid_hash.select { |k, v| v == [content] }
      type = type.keys[0].to_s
    else
      type = nil
    end
    return type
  end

  def print_out(queue_id, url, accessed, type, status, response_time, start_time)
    if output == "default"
      line_two = "Remaining: #{ queue.count } | Avg Req: #{ avg_response(response_time) }  | Total time: #{ (Time.now - start_time).round(2) } \r"
      print ' ' * (line_two.length) + "\r"
      print "#{ queue_id }: #{ url } \n"
      print line_two
      $stdout.flush
    elsif output == "verbose"
      puts "QueueID: #{ queue_id }
      Current URL: #{ url }
      Last Accessed: #{ accessed }
      Content Type: #{ type }
      Status Code: #{ status }
      Page Reponse Time: #{ response_time }
      Total Time: #{ Time.now - start_time } \n"
    end
  end

  def avg_response(time)
    @num_crawled += 1
    @average += time
    return (@average / @num_crawled).round(3)
  end

end
