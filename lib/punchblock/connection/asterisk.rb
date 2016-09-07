# encoding: utf-8

require 'ruby_ami'

module Punchblock
  module Connection
    class Asterisk < GenericConnection
      attr_reader :ami_client, :translator
      attr_accessor :event_handler

      def initialize(options = {})
        @stream_options = options.values_at(:host, :port, :username, :password)
        @ami_client = new_ami_stream
#        supervisor = Translator::Asterisk.supervise @ami_client, self
#        @translator = supervisor.actors.first
        @translator = { Translator::Asterisk.supervise(@ami_client, self) }.actors.first
        super()
      end

      def run
begin
        start_ami_client
rescue StandardError => ex
  pb_logger.error "[SG] caught internal error #{e.inspect}\n  #{(e.backtrace || ['EMPTY BACKTRACE']).join("\n  ")}"
end
  pb_logger.warn "[SG] the mess hall: @ami_client: #{@ami_client.inspect}. @translator: #{@translator.inspect}"
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
  pb_logger.info "[SG] new ami_client.object_id is #{ami_client.object_id.inspect}"
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
