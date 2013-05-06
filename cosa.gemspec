Gem::Specification.new do |s|
  s.name      = 'cosa'
  s.version   = '0.3.1'
  s.date      = '2013-04-29'
  s.summary   = "Cosa is a simple web crawler that generates a database for use by other tools and reports."
  s.platform    = Gem::Platform::RUBY
  s.license   = 'MIT'
  s.authors   = ["Matt Buresh", "Sam Parsons"]
  s.email     = 'mattburesh@gmail.com'
  s.files     = ["lib/cosa.rb", "lib/cli.rb", "lib/setup.rb", "lib/config.rb", "lib/crawler.rb", "lib/snapshot.rb"]
  s.homepage  = 'https://github.com/bsuweb/cosa/'
  s.executables << 'cosa'
  s.description   = <<-EOF
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
  EOF

  s.add_dependency "nokogiri", ">= 1.5.5"
  s.add_dependency "trollop", ">= 2.0"
  s.add_dependency "typhoeus", ">= 0.5.3"
  s.add_dependency "sequel", ">= 3.46.0"
  s.add_dependency "sqlite3", ">= 1.3.7"
end