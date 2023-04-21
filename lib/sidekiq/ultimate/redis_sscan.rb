# frozen_string_literal: true

module Sidekiq
  module Ultimate
    # Redis SSCAN helper. It uses cursor pagination to read all values from a set to avoid blocking redis.
    module RedisSscan
      class << self
        # @return [Array<String>] all values from a set
        def read(redis, key)
          cursor = "0"
          result = []
          loop do
            cursor, values = redis.sscan(key, cursor)
            result.push(*values)
            break if cursor == "0"
          end
          result.uniq! # Cursor is not atomic, so there may be duplicates because of concurrent update operations
          result
        end
      end
    end
  end
end
