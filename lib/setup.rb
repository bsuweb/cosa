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
  attr_accessor :opts, :db, :urls, :links, :queue, :meta, :domain, :start_time, :output, :num_crawled, :SHELF

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
    @meta = values["meta"]
    @domain = values["domain"]
    @exceptions = values["exceptions"]
    @SHELF = values["shelf"]

    clear_queue if opts[:clear_queue]
    list_queue if opts[:queue]
    add_to_queue(opts[:add]) if opts[:add]
    list(opts[:list]) if opts[:list]
    list_to(opts[:to]) if opts[:to]
    list_from(opts[:from]) if opts[:from]
    response_time(opts[:response_time]) if opts[:response_time]
    list_unresponsive if opts[:unresponsive]
    list_broken if opts[:broken]
    list_abandonded if opts[:abandoned]
    list_age(opts[:age]) if opts[:age]
    snapshot(opts[:snapshot]) if opts[:snapshot]
    exception(opts[:config], opts[:exception]) if opts[:exception]
    get_info(opts[:info]) if opts[:info]
    if opts[:crawl] then crawl(opts[:crawl]) else Process.exit end

    to_crawl = queue.where(:in_use => 1)
    to_crawl.each { |item| queue.where(:id => item[:id]).update(:in_use => 0) }
  end

  def clear_queue
    @queue.delete
  end

  def list_queue
    @queue.each { |x| puts x[:url] }
  end

  def add_to_queue(items)
    items.each { |x| insert_data_into(@queue, [x, '', 1, 0]) }
  end

  def list(type)
    @links.where(:type => type).group(:to_url).order{max(1)}.each { |x| puts x[:to_url] }
  end

  def list_to(item)
    @links.where(:to_url => item).each { |x| puts x[:from_url] }
  end

  def list_from(item)
    @links.where(:from_url => item).each { |x| puts x[:to_url] }
  end

  def response_time(resp_time)
    @urls.where{ response_time > resp_time }.each { |x| puts "#{ x[:url] } | #{ x[:response_time] }"}
  end

  def list_unresponsive
    @urls.where{ status > 500 }.each { |x| puts "#{ x[:url] } => #{ x[:status] }"}
  end

  def list_broken
    @urls.where(:status => 404).each do |bad_link|
      puts "BAD LINK: #{ bad_link[:url] }\nLINKED TO BY\n"
      @links.where(:to_url => bad_link[:url]).each { |x| puts "#{ x[:from_url] }"}
    end
  end

  def list_abandoned
    puts "Abandoned Links:"
    @urls.each do |x|
      unless @links[:to_url => x[:url]]
        puts x[:url]
      end
    end
  end

  def list_age(age)
    @urls.where{ accessed < Time.parse(age) }.each { |x| puts "#{ x[:url] } | #{ x[:accessed] }"}
  end

  def snapshot(snapshot)
    snap = Snapshot.new({:path => snapshot, :domain => @domain, :urls => @urls})
  end

  def exception(config, exception)
    if config.nil?
      puts 'Enter the name of the config file you would like to add an exception to:'
      inp = $stdin.gets.chomp
      file = YAML::load(File.open(inp))
      file["exceptions"] << exception
      File.open(Dir.pwd + '/' + inp, 'w+') {|f| f.write(file.to_yaml) }
    else
      file = YAML::load(File.open(config))
      file["exceptions"] << exception
      File.open(Dir.pwd + '/' + config, 'w+') {|f| f.write(file.to_yaml) }
    end
  end

  def get_info(info)
    url = @urls.where(:url => info).limit(1)
    puts info
    url.each do |x|
      @meta.where(:id => x[:id]).each { |y| puts "#{ y[:key] }: #{ y[:value] }" }
    end
  end

  def crawl(crawl)
    if crawl.length == 1
      insert_data_into(@queue, [ crawl, '', 1, 0 ])
    elsif crawl.length == 2
      pattern = URI.join( crawl[0], crawl[1]).to_s
      insert_data_into(@queue, [ crawl[0], pattern, 1, 0 ])
    end
  end

end
