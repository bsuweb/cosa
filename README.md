# crawler

## Dependencies

The crawler relies on the following ruby gems.

* [Typhoeus](https://github.com/typhoeus/typhoeus), a library for running HTTP requests

        gem install typhoeus

* [Sequel](http://sequel.rubyforge.org/), a database toolkit

        gem install sequel

* [Nokogiri](http://nokogiri.org/), an HTML parser

        gem install nokogiri

If you run into difficulty see [Installing Nokogiri](http://nokogiri.org/tutorials/installing_nokogiri.html).


## Running the Crawler

First, rename sample_config.yaml to config.yaml and modify it to meet your needs.

You have three options when running the crawler:

        ruby crawler.rb http://www.example.com
        
The crawler will start at this address, and crawl every page on the site.

        ruby crawler.rb http://www.example.com/directory/ /directory/page/
        
The crawler will start at http://www.example.com/directory/, and then only add links to the queue if they contain the pattern of http://www.example.com/directory/page/

        ruby crawler.rb
        
If you have already run the crawler, this will check the first link in the urls table and see if it has been crawled within the shelf time(default 1 day). If it hasn't, that url will be added to the queue and the site will be recrawled.
