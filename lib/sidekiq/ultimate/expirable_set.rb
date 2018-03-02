# frozen_string_literal: true

require "monitor"

require "concurrent/utility/monotonic_time"

module Sidekiq
  module Ultimate
    # List that tracks when elements were added and enumerates over those not
    # older than `ttl` seconds ago.
    #
    # ## Implementation
    #
    # Internally list holds an array of arrays. Thus ecah element is a tuple of
    # monotonic timestamp (when element was added) and element itself:
    #
    #     [
    #       [ 123456.7890, "default" ],
    #       [ 123456.7891, "urgent" ],
    #       [ 123457.9621, "urgent" ],
    #       ...
    #     ]
    #
    # It does not deduplicates elements. Eviction happens only upon elements
    # retrieval (see {#each}).
    #
    # @see http://ruby-concurrency.github.io/concurrent-ruby/Concurrent.html#monotonic_time-class_method
    # @see https://ruby-doc.org/core/Process.html#method-c-clock_gettime
    # @see https://linux.die.net/man/3/clock_gettime
    #
    # @private
    class ExpirableSet
      include Enumerable

      # Create a new ExpirableSet instance.
      #
      # @param ttl [Float] elements time-to-live in seconds
      def initialize(ttl)
        @ttl = ttl.to_f
        @set = {}
        @mon = Monitor.new
      end

      # Pushes given element into the set.
      #
      # @params element [Object]
      # @return [ExpirableSet] self
      def <<(element)
        @mon.synchronize { @set[element] = Concurrent.monotonic_time + @ttl }
        self
      end

      # Evicts expired elements and calls the given block once for each element
      # left, passing that element as a parameter.
      #
      # @yield [element]
      # @return [Enumerator] if no block given
      # @return [ExpirableSet] self if block given
      def each(&block)
        return to_enum __method__ unless block_given?

        elements = []

        # Evict expired elements
        @mon.synchronize do
          horizon = Concurrent.monotonic_time
          @set.each { |k, v| v < horizon ? @set.delete(k) : (elements << k) }
        end

        elements.each(&block)

        self
      end
    end
  end
end
