require 'trollop'
require './options'

class Database
  attr_accessor :opts, :db, :urls, :links, :queue, :SHELF, :domain, :start_time, :output

  def initialize
    opts = Trollop::options do
      version " Cosa 0.1"
      banner <<-EOS
      Cosa is a simple web crawler that generates a database for use by other
      tools and reports.

      Usage:
        ruby cosa.rb -w http://www.example.com [-options]
          - Cosa will start at this address, and crawl every page on the site.

        ruby cosa.rb -w http://www.example.com/directory/ /directory/page/ [-options]
          - Cosa will start at 'http://www.example.com/directory/', and then
            only add links to the queue if they contain the pattern
            'http://www.example.com/directory/page'.

        [DEPRECATED]
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
      opt :crawl, "Start the crawler.", :type => :strings
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

    # Make sure :age date is valid
    if opts[:age] then Trollop::die :age, "Date must be in the form of yyyy-mm-dd" unless opts[:age].to_s.match(/[0-9]{4}-[0-9]{2}-[0-9]{2}/) end

    # Make sure the given config file ends in .yaml
    # May change to check if the given name when appended with .yaml is valid
    if opts[:config] then Trollop::die :config, "Config file must end in .yaml" unless opts[:config].to_s.match(/.yaml$/) end

  set_opts(opts)
  end

end