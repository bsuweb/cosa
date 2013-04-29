require 'sequel'
require 'yaml'
require 'uri'
require 'config'
require 'crawler'
require 'snapshot'

# Set defaults
# Handle Command Line Options
class Cosa
  extend Configure
  attr_accessor :opts, :db, :urls, :links, :queue, :SHELF, :domain, :start_time, :output, :num_crawled

  def setup(opts)
    values = Cosa.config(opts[:config], opts[:init])
    @output = "silent" if opts[:silent]
    @output ||= "verbose" if opts[:verbose]
    @output ||= "default"

    @num_crawled = 0
    @average = 0
    @start_time = Time.now
    @db = values["db"]
    @urls = values["urls"]
    @links = values["links"]
    @queue = values["queue"]
    @domain = values["domain"]
    @SHELF = values["shelf"]
    @exceptions = values["exceptions"]

    if opts[:clear_queue] then clear_queue(@queue) end
    if opts[:queue] then list_queue(@queue) end
    if opts[:add] then add_to_queue(opts[:add], @queue) end
    if opts[:css] then list_css(@links) end
    if opts[:to] then list_to(opts[:to], @links) end
    if opts[:from] then list_from(opts[:from], @links) end
    if opts[:response_time] then response_time(opts[:response_time], @url) end
    if opts[:unresponsive] then list_unresponsive(@url) end
    if opts[:broken] then list_broken(@url, @links) end
    if opts[:abandoned] then list_abandoned(@url, @links) end
    if opts[:age] then list_age(opts[:age], @url) end
    if opts[:snapshot] then snapshot(opts[:snapshot]) end
    if opts[:crawl] then crawl(opts[:crawl], @queue) else Process.exit end

    to_crawl = queue.where(:in_use => 1)
    to_crawl.each { |item| queue.where(:id => item[:id]).update(:in_use => 0) }
  end

  def clear_queue(queue)
    queue.delete
  end

  def list_queue(queue)
    queue.each { |x| puts x[:url] }
  end

  def add_to_queue(items, queue)
    items.each { |x| insert_data_into(queue, [x, '', 1, 0]) }
  end

  def list_css(links)
    links.where(:type => 'css').group(:to_url).order{max(1)}.each { |x| puts x[:to_url] }
  end

  def list_to(item, links)
    links.where(:to_url => item).each { |x| puts x[:from_url] }
  end

  def list_from(item, links)
    links.where(:from_url => item).each { |x| puts x[:to_url] }
  end

  def response_time(resp_time, urls)
    urls.where{ response_time > resp_time }.each { |x| puts "#{ x[:url] } | #{ x[:response_time] }"}
  end

  def list_unresponsive(urls)
    urls.where{ status > 500 }.each { |x| puts "#{ x[:url] } => #{ x[:status] }"}
  end

  def list_broken(urls, links)
    urls.where(:status => 404).each do |bad_link|
      puts "BAD LINK: #{ bad_link[:url] }\nLINKED TO BY\n"
      links.where(:to_url => bad_link[:url]).each { |x| puts "#{ x[:from_url] }"}
    end
  end

  def list_abandoned(urls, links)
    puts "Abandoned Links:"
    urls.each do |x|
      unless links[:to_url => x[:url]]
        puts x[:url]
      end
    end
  end

  def list_age(age, urls)
    urls.where{ accessed < Time.parse(age) }.each { |x| puts "#{ x[:url] } | #{ x[:accessed] }"}
  end

  def snapshot(snapshot)
    snap = Snapshot.new({:path => snapshot, :domain => @domain, :urls => @urls})
  end

  def crawl(crawl, queue)
    if crawl.length == 1
      insert_data_into(queue, [ crawl, '', 1, 0 ])
    elsif crawl.length == 2
      pattern = URI.join( crawl[0], crawl[1]).to_s
      insert_data_into(queue, [ crawl[0], pattern, 1, 0 ])
    else
    end
  end

end
