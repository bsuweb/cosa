require 'trollop'
require 'setup'

class Cosa
  def cli
    sub_commands = %w(crawl)
    opts = Trollop::options do
      version "Cosa v#{@@VERSION}"
      banner <<-EOS
      Cosa is a simple web crawler that generates a database for use by other
      tools and reports.

      Usage:
        cosa crawl
          - Resume crawling from the first item in the queue.

        cosa crawl http://www.example.com [-options]
          - Cosa will start at this address, and crawl every page on the site.

        cosa crawl http://www.example.com/directory/ /directory/page/ [-options]
          - Cosa will start at 'http://www.example.com/directory/', and then
            only add links to the queue if they contain the pattern
            'http://www.example.com/directory/page'.

        Because Cosa stores the queue in the database, you can quit the program
        at any time and when you restart it, it will begin where it left off.
      EOS

      opt :init, "Command-line tool for creating and saving a config file."
      opt :add, "Add a URL (or multiple URLs, separated by spaces) to the queue.", :type => :strings
      opt :config, "Run Cosa with a given config file. Otherwise, Cosa will use the default config if it exists", :type => :string
      opt :broken, "List all URLs that contain broken links, and their broken links."
      opt :abandoned, "List all pages that are no longers linked to."
      opt :exception, "Add a regex exception to the config file given with the -c flag.", :type => :string, :short => '-x'
      opt :info, "Get information about the given url.", :type => :strings, :short => '-I'
      # opt :invalid_html, "List pages with invalid html."
      opt :list, "List all URLs of the given type.", :type => :string
      opt :age, "List all URLs that are older than the given date.", :type => :string
      opt :queue, "List the current queue."
      opt :clear_queue, "Empty the queue", :short => '-e'
      opt :response_time, "List the URLs that took longer than <seconds> to respond.", :type => :float, :short => '-r'
      opt :unresponsive, "List URLs that were not responsive.", :short => '-u'
      opt :to, "List URLs that link to the given URL.", :type => :string
      opt :from, "List URLs that the given URL links to.", :type => :string, :short => '-f'
      opt :silent, "Silence all output.", :short => 'S'
      opt :snapshot, "Export the entire site from cosa as an HTML snapshot to the given full path.", :type => :string, :short => "-o"
      opt :verbose, "Verbose output.", :short => "-V"
      stop_on sub_commands
    end

    while !ARGV.empty?
    cmd = ARGV.shift # get the subcommand
    cmd_opts = case cmd
      when "crawl" # parse crawl options
        if ARGV.count() > 1
          new_opts = {:crawl=>[ ARGV[0], ARGV[1] ]}
        elsif ARGV.count() < 1
          new_opts = {:crawl=>[true]}
        else
          new_opts = {:crawl=>[ARGV[0]]}
        end
      end
    end
    if new_opts then opts = opts.merge(new_opts) end

    # Make sure :age date is valid
    if opts[:age] then Trollop::die :age, "Date must be in the form of yyyy-mm-dd" unless opts[:age].to_s.match(/[0-9]{4}-[0-9]{2}-[0-9]{2}/) end

    # Make sure the given config file ends in .yaml
    # May change to check if the given name when appended with .yaml is valid
    if opts[:config] then Trollop::die :config, "Config file must end in .yaml" unless opts[:config].to_s.match(/.yaml$/) end


    return opts
  end
end
