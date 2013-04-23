require './cli'
require './setup'

crawler = Cosa.new(cli)

# Check the next item in the queue as long as the queue is not empty
while true
  if !crawler.queue.empty?
    crawler.crawl_queue
  else
    unless crawler.output == 'silent'
      print "\n"
    end
    break
  end
end