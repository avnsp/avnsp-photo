#require './lib/thumper/version'
require 'bunny'
require 'json'

module Thumper
  class Base
    def initialize(publish_to: nil, consume_from: nil, config: {timeout: 20})
      @consumers = []
      @pub = Bunny.new(publish_to, config)
      @pub.start
      @pub_chan = @pub.create_channel
      @sub = Bunny.new(consume_from, config)
      @sub.start
    end

    def with_channel(prefetch: 1, &blk)
      ch = @sub.create_channel(nil, prefetch)
      ch.prefetch prefetch
      yield Group.new(ch, @pub_chan, @consumers)
    end

    class Group
      def initialize(ch, pub_chan, consumers)
        @sub_ch = ch
        @pub_ch = pub_chan
        @consumers = consumers
      end

      def subscribe(qname, *topics, &blk)
        q = @sub_ch.queue qname, durable: qname != "", auto_delete: qname == ""
        t = @sub_ch.topic 'amq.topic', durable: true
        topics.each do |topic|
          q.bind(t, routing_key: topic)
        end
        c = q.subscribe(ack: true, block: false) do |delivery, headers, body|
          sleep 2 if delivery.redelivered?
          begin
            data = parse(headers.content_type, body)
            #puts "<= #{qname} #{delivery.routing_key} #{body}"
            blk.call data, delivery.routing_key, headers
            @sub_ch.acknowledge(delivery.delivery_tag, false)
          rescue Exception => e
            topic = delivery.routing_key
            puts "[ERROR] #{qname} failed to process #{topic}: #{e.inspect}"
            puts "#{e}\n  #{e.backtrace.join("\n  ")}"
            @sub_ch.reject(delivery.delivery_tag, true)
          end
        end
        @consumers << c
        c
      end

      def publish(topic, data)
        puts "=> #{topic} #{data}"
        t = @pub_ch.topic 'amq.topic', durable: true
        t.publish(data.to_json, 
                  routing_key: topic, 
                  content_type: 'application/json', 
                  persistent: true)
      end

      private
      def parse(content_type, body)
        case content_type 
        when 'application/json' then JSON.parse body, symbolize_names: true
        when 'text/plain' then body
        else raise "Unknown content type #{content_type}" 
        end
      end
    end

    def stop
      @consumers.each { |c| c.cancel }
      @pub.close
      @sub.close
    end
  end
end
