# encoding: utf-8

require 'ruby_ami'



# Monkey Patch to allow pool size of 1.  Yay!!!!
module Celluloid
  class PoolManager
    def initialize(worker_class, options = {})
      @size = options[:size] || [Celluloid.cores, 2].max
      raise ArgumentError, "minimum pool size is 1" if @size < 1

      @worker_class = worker_class
      @args = options[:args] ? Array(options[:args]) : []

      @idle = @size.times.map { worker_class.new_link(*@args) }

      # FIXME: Another data structure (e.g. Set) would be more appropriate
      # here except it causes MRI to crash :o
      @busy = []
    end
  end
end


module Punchblock
  module Connection
    class Asterisk < GenericConnection
      attr_reader :ami_client, :translator
      attr_accessor :event_handler

      def initialize(options = {})
        @stream_options = options.values_at(:host, :port, :username, :password)
        @ami_client = new_ami_stream
        @translator = Translator::Asterisk.pool size: 1, args: [@ami_client, self]
        super()
      end

      def run
begin
        start_ami_client
rescue StandardError => ex
  pb_logger.error "[SG] re-raising internal error #{e.inspect}\n  #{(e.backtrace || ['EMPTY BACKTRACE']).join("\n  ")}"
  raise ex
end
  pb_logger.warn "[SG] the mess hall: @ami_client: #{@ami_client.object_id.inspect} #{@ami_client.inspect}. @translator: #{@translator.object_id.inspect} #{@translator.inspect}"
        raise DisconnectedError
      end

      def stop
        translator.terminate
        ami_client.terminate
      end

      def write(command, options)
        translator.async.execute_command command, options
      end

      def send_message(*args)
        translator.send_message *args
      end

      def handle_event(event)
        event_handler.call event
      end

      def new_ami_stream
        stream = RubyAMI::Stream.new(*@stream_options, ->(event) { translator.async.handle_ami_event event }, pb_logger)
        client = (ami_client || RubyAMIStreamProxy.new(stream))
        client.stream = stream
        client
      end

      def start_ami_client
        @ami_client = new_ami_stream unless ami_client.alive?
  pb_logger.info "[SG] new @ami_client.object_id is #{@ami_client.object_id.inspect}"
        ami_client.async.run
        Celluloid::Actor.join(ami_client)
  pb_logger.warn "[SG] start_ami_client is exited 'cleanly'"
      end

      def new_call_uri
        Punchblock.new_uuid
      end
    end

    class RubyAMIStreamProxy
      attr_accessor :stream

      def initialize(ami)
        @stream = ami
      end

      def method_missing(method, *args, &block)
        stream.__send__(method, *args, &block)
      end

    end
  end
end
