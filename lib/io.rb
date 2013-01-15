require 'trollop'

def cli
  opts = Trollop::options do
    version " Cosa 0.1"
    banner <<-EOS
    Cosa is a simple web crawler that generates a database for use by other
    tools and reports.

    Usage:
      ruby cosa.rb http://www.example.com
        - Cosa will start at this address, and crawl every page on the site.

      ruby cosa.rb http://www.example.com/directory/ /directory/page/
        - Cosa will start at 'http://www.example.com/directory/', and then
          only add links to the queue if they contain the pattern
          'http://www.example.com/directory/page'.

      ruby cosa.rb
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
    opt :crawl, "Start the crawler. Optional switches for silent or verbose output.", :type => :string
    opt :broken, "List all URLs that contain broken links and their broken links."
    opt :abandoned, "List all pages that are no longers linked to."
    opt :invalid_html, "List pages with invalid html."
    opt :css, "List all CSS URLs that are linked to."
    opt :age, "List all URLs that are older than the given date.", :type => :string
    opt :queue, "List the current queue."
    opt :clear_queue, "Empty the queue"
    opt :response_time, "List the URLs that took longer than <seconds> to responsd.", :type => :integer
    opt :unresponsive, "List URLs that were not responsive."
    opt :to, "List URLs that link to the given URL.", :type => :string
    opt :from, "List URLs that the given URL links to.", :type => :string
    opt :silent, "Silence all output."
    opt :snapshot, "Export the entire site from cosa as an HTML snapshot to the given path.", :type => :string
    opt :verbose, "Verbose output."
  end
  return opts
end

#---OUTPUT---
def verbose_output(id, url, accessed, type, status, response_time, runtime)
  puts "Queue ID: #{ id }
  Current URL: #{ url }
  Last Accessed: #{ accessed }
  Content Type: #{ type }
  Status Code: #{ status }
  Page Response Time: #{ response_time }
  Total Time: #{ runtime }
  \n"

end

def default_output(id, url, runtime, avg_req)

  printf "\rURL: #{ url } | Queue: #{ id } Avg Req: #{ avg_req }   Total: #{ runtime }"
  $stdout.flush
end


#might move these functions, and will most likely combine them.
def commands(cosa, opts)

  # init_config if opts[:init]

  # insert_data(cosa, cosa.queue, [ opts[:add][0], opts[:add][1], opts[:add][3] ]) if opts[:add]

  # list_broken if opts[:broken]

  # list_abandoned if opts[:abandoned]

  # list_invalid if opts[:invalid_html]

  # list_css if opts[:css]

  # list_age(opts[:date]) if opts[:date]

  # list_queue if opts[:queue]

  # clear_queue if opts[:clear_queue]

  # list_response_time(opts[:response_time]) if opts[:response_time]

  # list_unresponsive if opts[:unresponsive]

  # list_to if opts[:to]

  # list_from if opts[:from]

  # take_snapshot if opts[:snapshot]

end

def clear_queue
  queue.delete
end

def list_queue
  queue.each { |x| puts x[:url] }
end

def list_css
  urls.where(:content_type => "text/css").each { |x| puts x[:url] }
end
