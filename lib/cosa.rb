#!/usr/bin/env ruby

require 'cli'
require 'setup'

class Cosa
  attr_accessor :VERSION
  def initialize
    @@VERSION = "0.3.1"
    setup(cli)
    while true
      if !queue.empty?
        crawl_queue
      else
        db.run("DELETE FROM queue")
        db.run("DELETE FROM sqlite_sequence WHERE name='queue'")
        unless output == 'silent'
          print "\n"
        end
        break
      end
    end
  end

end