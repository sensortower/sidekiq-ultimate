# frozen_string_literal: true

require "monitor"

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
    # @see https://ruby-doc.org/core/Process.html#method-c-clock_gettime
    # @see https://linux.die.net/man/3/clock_gettime
    #
    # @private
    class ExpirableSet
      include Enumerable

      # Create a new ExpirableSet instance.
      def initialize
        @set = Hash.new(0.0)
        @mon = Monitor.new
      end

      # Allow implicit coercion to Array:
      #
      #     ["x"] + ExpirableSet.new.add("y", :ttl => 10) # => ["x", "y"]
      #
      # @return [Array]
      alias to_ary to_a

      # Adds given element into the set.
      #
      # @params element [Object]
      # @param ttl [Numeric] elements time-to-live in seconds
      # @return [ExpirableSet] self
      def add(element, ttl:)
        @mon.synchronize do
          expires_at = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + ttl

          # do not allow decrease element's expiry
          @set[element] = expires_at if @set[element] < expires_at
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
          horizon = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          @set.each { |k, v| yield(k) if horizon <= v }
        end

        self
      end
    end
  end
end
