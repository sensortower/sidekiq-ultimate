# frozen_string_literal: true

require "redis"

module Sidekiq
  module Ultimate
    # Redis-rb 4.2.0 renamed `#exists` to `#exists?` and changed behaviour of `#exists` to return integer
    # https://github.com/redis/redis-rb/blob/master/CHANGELOG.md#420
    module UseExistsQuestionMark
      def self.use?
        return @use if defined?(@use)

        @use = Gem::Version.new(Redis::VERSION) >= Gem::Version.new("4.2.0")
      end
    end
  end
end
