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

Then, open the sqlite database and insert the first url to be crawled to the urls table.

        INSERT INTO urls VALUES ("www.website.com/", 0, "text/html", 1, 200, "html", 1);

To start the crawler, run the following from the crawler directory.

        ruby crawler.rb

For the time being, the crawler will take care of the rest.