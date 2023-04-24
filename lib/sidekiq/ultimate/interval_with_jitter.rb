# frozen_string_literal: true

module Sidekiq
  module Ultimate
    # Util class to add a jitter to the interval
    class IntervalWithJitter
      RANDOM_OFFSET_RATIO = 0.1

      class << self
        # Returns execution interval with jitter.
        # Jitter is +- RANDOM_OFFSET_RATIO from the original value.
        def call(interval)
          jitter_factor = 1 + rand(-RANDOM_OFFSET_RATIO..RANDOM_OFFSET_RATIO)
          jitter_factor * interval
        end
      end
    end
  end
end
