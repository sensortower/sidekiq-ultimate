# frozen_string_literal: true

require "monitor"

require "concurrent/utility/monotonic_time"

require "sidekiq/ultimate/debugging"

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
      include Debugging

      # Create a new ExpirableSet instance.
      def initialize
        @set = {}
        @mon = Monitor.new
      end

      alias to_ary to_a

      # Adds given element into the set.
      #
      # @params element [Object]
      # @param ttl [Numeric] elements time-to-live in seconds
      # @return [ExpirableSet] self
      def add(element, ttl:)
        @mon.synchronize do
          expires_at = Concurrent.monotonic_time + ttl

          # do not allow decrease element's expiry
          if @set[element] && @set[element] >= expires_at
            debug! do
              "#{element}'s expiry kept as is: #{@set[element]}; " \
                "proposed expiry was: #{expires_at}"
            end
          else
            @set[element] = expires_at
            debug! { "#{element}'s expiry set to: #{expires_at}" }
          end
        end

        self
      end

      # Evicts expired elements and calls the given block once for each element
      # left, passing that element as a parameter.
      #
      # @yield [element]
      # @return [Enumerator] if no block given
      # @return [ExpirableSet] self if block given
      def each
        return to_enum __method__ unless block_given?

        @mon.synchronize do
          horizon = Concurrent.monotonic_time

          debug! { "Yielding elements above #{horizon} horizon" }

          @set.each { |k, v| v < horizon ? @set.delete(k) : yield(k) }
        end

        self
      end
    end
  end
end
