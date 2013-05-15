# Cosa

Cosa is a simple web crawler that generates a database for use by other tools and reports.

It starts with a URL and domain name and will parse links returned by that URL, check all links to web pages, images, CSS, and script files. Links to HTML pages on the same domain will be recursively parsed until the queue finishes. Results from each URL and the link structure are contained in the database.

Cosa will only re-crawl URL's when the shelf life has expired or when specifically requested to re-fetch a URL. The default shelf life is one day, this can be changed in the config.


## Dependencies

Cosa relies on the following ruby gems.

* [Typhoeus](https://github.com/typhoeus/typhoeus), a library for running HTTP requests

        gem install typhoeus

* [Sequel](http://sequel.rubyforge.org/), a database toolkit

        gem install sequel

* [Trollop](http://trollop.rubyforge.org/), a command line option parser.

        gem install trollop

* [RMagic](http://rmagick.rubyforge.org/), an interface between Ruby and the ImageMagick and GraphicsMagick image processing libraries.

        gem install rmagick
        
RMagick requires the ImageMagick library, which can be downloaded [here](http://www.imagemagick.org/script/binary-releases.php)

* [Nokogiri](http://nokogiri.org/), an HTML parser

        gem install nokogiri

If you run into difficulty see [Installing Nokogiri](http://nokogiri.org/tutorials/installing_nokogiri.html).

## Installing Cosa

After downloading Cosa run `gem build cosa.gemspec` followed by `sudo gem install cosa-0.3.1.gem` in the directory
where Cosa is located.

## Running Cosa

First, rename `sample_config.yaml` to `config.yaml` and modify it to meet your needs.

You have three options when running Cosa.

      cosa crawl
Resume crawling from the first item in the queue.

      cosa crawl http://www.example.com [-options]
Cosa will start at this address, and crawl every page on the site.

      cosa crawl http://www.example.com/directory/ /directory/page/ [-options]
Cosa will start at 'http://www.example.com/directory/', and then only add links to the queue if they contain the pattern 'http://www.example.com/directory/page'.

Because Cosa stores the queue in the database, you can quit the program at any time and when you restart it will begin where it left off.

## Using the data Cosa generates

Cosa uses a simple database with the following three tables:

* `urls` – each URL linked to from the site. Contains: `url`, `date_accessed`, `content_type`, `content_length`, `status`, `response` (the entire HTTP response body), `validation_type`, and `valid`
* `links` – stores the relationship between URL's. Once the crawl is complete, you can query this table to determine all URL's a given URL links to, and all URL's that link to a given URL.
* `queue` working list of URL's that need to be crawled.

## Help

```
Usage: cosa crawl OR crawl [starting_url] OR crawl [starting_url pattern]
                    [-i] [-n] [-b] [-u] [-q] [-e] [-S/-V] [-v] [-h]
                    [-a url_one url_two] [-c config_file]
                    [-l type] [-x exception] [-o /path/to/snapshot]
                    [-g date] [-r seconds] [-t URL] [-f URL] [-I URL]

Commands:
crawl                   : Start the crawler. Look above for examples of usage.

Options:
--init, -i              : Command-line tool for creating and saving a config file.
--add, -a <s+>          : Add a URL (or multiple URLs, separated by spaces) to the queue.
--config, -c <s>        : Run Cosa with a given config file. Otherwise, Cosa will use the default config if it exists.
--broken, -b            : List all URLs that contain broken links, and their broken links.
--abandoned, -n         : List all pages that are no longer linked to.
--exception, -x <s>     : Add a regex exception to the config file given with the -c flag.
--info, -I <s>          : Get information about the given url.
--list, -l <s>          : List all URLs of the given type.
--age, -g <s>           : List all URLs that are older than the given date.
--queue, -q             : List all URLs in the queue.
--clear-queue, -e       : Empty the queue.
--response-time, -r <f> : List all URLs that took longer than <seconds> to respond.
--unresponsive, -u      : List all URLs that were not responsive.
--to, -t <s>            : List all URLs that link to the given URL.
--from, -f <s>          : List all URLs that the given URL links to.
--silent, -S            : Silence all output.
--snapshot, -o <s>      : Export the entire site from Cosa as an HTML snapshot to the given full path.
--verbose, -V           : Verbose output.
--version, -v           : Print version and exit.
--help, -h              : Show this message.
```

Cosa currently supports SQLite and MySQL.

## Juan de la Cosa

We named Cosa after [Juan de la Cosa](http://en.wikipedia.org/wiki/Juan_de_la_Cosa).

> He made the earliest extant European world map to incorporate the territories of the Americas that were discovered in the 15th century, sailed with Christopher Columbus on his first three voyages, and was the owner/captain of the Santa María.

## License

Cosa is released under the [MIT License](http://opensource.org/licenses/MIT).

Copyright (C) 2012-2013 Bemidji State University

## Changelog

[v0.3 (2013-05-01](https://github.com/bsuweb/cosa/tree/v0.3)
 * Base code completely rewritten
 * Performance increases
 * Numerous bug fixes
 * Removed List CSS option
 * Added List option
 * Added Snapshot option
 * Added Exceptions


[v0.2 (2013-02-13)](https://github.com/bsuweb/cosa/tree/v0.2)
 * Cosa now stores a response time for each url.
 * Slight performance increases.
 * Restructured files
 * Added mysql support
 * Added Command Line Interface with support for:
  * List all queue items
  * List all CSS files
  * List all urls that a given page links to
  * List all urls that link to a given url
  * List all urls that took longer than a given time to respond
  * List al unresponsive urls
  * List all broken links
  * List all urls that were crawled prior to a given date
  * Clear the queue
  * Add items to queue
  * Can supply a custom configuration file
  * Default/Silent/Verbose output



[v0.1 (2013-01-09)](https://github.com/bsuweb/cosa/tree/v0.1)
 * Crawls a given webpage, and any connected pages.
 * Crawls a given webpage, and any connected pages matching a given pattern.
 * Re-crawls a site if it has bot been crawled within a given time.
 * Stores data from crawled pages in an SQLite database
