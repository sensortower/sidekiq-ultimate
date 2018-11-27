# frozen_string_literal: true

require "sidekiq/util"

module Sidekiq
  module Ultimate
    # Helper object that extend queue name string with redis keys.
    #
    # @private
    class QueueName
      # Regexp used to normalize (possibly) expanded queue name, e.g. the one
      # that is returned upon redis BRPOP
      QUEUE_PREFIX_RE = %r{.*queue:}
      private_constant :QUEUE_PREFIX_RE

      # Internal helper context.
      Helper = Module.new { extend Sidekiq::Util }
      private_constant :Helper

      # Original stringified queue name.
      #
      # @example
      #
      #   queue_name.normalized # => "foobar"
      #
      # @return [String]
      attr_reader :normalized
      alias to_s normalized

      # Create a new QueueName instance.
      #
      # @param normalized [#to_s] Normalized (without any namespaces or `queue:`
      #   prefixes) queue name.
      # @param identity [#to_s] Sidekiq process identity.
      def initialize(normalized, identity: self.class.process_identity)
        @normalized = -normalized.to_s
        @identity   = -identity.to_s
      end

      # @!attribute [r] hash
      #
      #   A hash based on the normalized queue name.
      #
      #   @see https://ruby-doc.org/core/Object.html#method-i-hash
      #   @return [Integer]
      def hash
        @hash ||= @normalized.hash
      end

      # @!attribute [r] pending
      #
      #   Redis key of queue list.
      #
      #   @example
      #
      #       queue_name.pending # => "queue:foobar"
      #
      #   @return [String]
      def pending
        @pending ||= -"queue:#{@normalized}"
      end

      # @!attribute [r] inproc
      #
      #   Redis key of in-process jobs list.
      #
      #   @example
      #
      #       queue_name.inproc # => "inproc:argentum:12345:a9b8c7d6e5f4:foobar"
      #
      #   @return [String]
      def inproc
        @inproc ||= -"inproc:#{@identity}:#{@normalized}"
      end

      # Check if `other` is the {QueueName} representing same queue.
      #
      # @example
      #
      #     QueueName.new("abc").eql? QueueName.new("abc") # => true
      #     QueueName.new("abc").eql? QueueName.new("xyz") # => false
      #
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(self.class) && @normalized == other.normalized
      end
      alias eql? ==

      # Returns human-friendly printable QueueName representation.
      #
      # @example
      #
      #     QueueName.new("foobar").inspect   # => QueueName["foobar"]
      #     QueueName["queue:foobar"].inspect # => QueueName["foobar"]
      #
      # @return [String]
      def inspect
        "#{self.class}[#{@normalized.inspect}]"
      end

      # Returns new QueueName instance with normalized queue name. Use this
      # when you're not sure if queue name is normalized or not (e.g. with
      # queue name received as part of BRPOP command).
      #
      # @example
      #
      #   QueueName["ns:queue:foobar"].normalized # => "foobar"
      #
      # @param name [#to_s] Queue name
      # @param kwargs (see #initialize for details on possible options)
      # @return [QueueName]
      def self.[](name, **kwargs)
        new(name.to_s.sub(QUEUE_PREFIX_RE, "").freeze, **kwargs)
      end

      def self.process_identity
        Helper.identity
      end
    end
  end
end
