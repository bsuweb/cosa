Gem::Specification.new do |s|
  s.name      = 'cosa'
  s.version   = '0.3'
  s.date      = '2013-04-29'
  s.summary   = "Cosa"
  s.platform    = Gem::Platform::RUBY
  s.description   = "Cosa is a simple web crawler that generates a database for use by other tools and reports."
  s.license   = 'MIT'
  s.authors   = ["Matt Buresh", "Sam Parsons"]
  s.email     = 'mattburesh@gmail.com'
  s.files     = ["lib/cosa.rb", "lib/cli.rb", "lib/setup.rb", "lib/config.rb", "lib/crawler.rb", "lib/snapshot.rb"]
  s.homepage  = 'https://github.com/bsuweb/cosa/'
  s.executables << 'cosa'

  s.add_dependency "nokogiri", ">= 1.5.5"
  s.add_dependency "trollop", ">= 2.0"
  s.add_dependency "typhoeus", ">= 0.5.3"
  s.add_dependency "sequel", ">= 3.46.0"
  s.add_dependency "sqlite3", ">= 1.3.7"
end