require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'rexml/document'

#Runs the given page through the w3 validator. And returns whether the page
#is valid or invalid
#
# * *Args*    :
#   - +page+          -> URL to be validated
#   - +content_type+  -> Content type of the page
# * *Returns* :
#   - a boolean representing the validity of +page+
#
def valid?(page, content_type)
  content = content_type.to_s
  puts content
  valid = nil
  valid_array = [{html: "text/html"}, {xml: "text/xml"}, {css: "text/css"}, {rss: "application/rss+xml"}, {rss: "application/rdf+xml"}, {rss: "application/atom+xml"}]

  valid_hash = Hash.new { |h, k| h[k] = [] }

  valid_array.each do |entry|
    entry.each_pair { |k, v| valid_hash[k] << v }
  end

  if valid_hash.has_value?([content])

    type = valid_hash.select { |k, v| v == [content] }
    type = type.keys[0].to_s

  else
    type = nil
  end
  puts type
  # begin
  # REXML::Document.new(page)
  # rescue REXML::ParseException
  #   return [0, type]
  # end
  return [1, type.to_s]

  # `curl -s #{ page } | tidy -q --show-warnings false --show-errors 0`

  # if $?.exitstatus == 0 || $?.exitstatus == 1
  #  return [1, type]
  # else
  #   return [0, type]
  # end


end