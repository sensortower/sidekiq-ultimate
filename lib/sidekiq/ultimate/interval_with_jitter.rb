# frozen_string_literal: true

module Sidekiq
  module Ultimate
    # Util class to add a jitter to the interval
    class IntervalWithJitter
      RANDOM_OFFSET_RATIO = 0.1

      class << self
        # Returns execution interval with jitter.
        # Jitter is +- RANDOM_OFFSET_RATION from the original value.
        def call(interval)
          jitter_ratio = (rand(0..RANDOM_OFFSET_RATIO) * 2) - RANDOM_OFFSET_RATIO
          interval + (jitter_ratio * interval)
        end
      end
    end
  end
end
