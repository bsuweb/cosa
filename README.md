`crawler` is a simple web crawler that builds a database of URL's for use with by tools and reports. 

It starts with a URL and domain name and will parse links returned by that URL, check all links to web pages, images, CSS, and script files. Links to HTML pages on the same domain will be recursively parsed until the queue finishes. Results from each URL and the link structure are contained in the database. 

The crawler will only re-crawl URL's when the shelf life has expired or when specifically requested to re-fetch a URL. The default shelf life is one day, this can be changed in the config.

The database is fairly simple, with the following three tables:

* `urls` – each URL linked to from the site. Contains: `url`, `date_accessed`, `content_type`, `content_length`, `status`, `response` (the entire HTTP response body), `validation_type`, and `valid`
* `links` – stores the relationship between URL's. Once the crawler is complete, you can query this table to determine all URL's a given URL links to, and all URL's that link to a given URL.
* `queue` working list of URL's that are left to crawl before the crawler is done.

Because the crawler stores its `queue` or current state in the database, you can quit the program at any time and when you restart it will begin where it left off.

Currently it only supports SQLite although support for MySQL is planned. 

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
