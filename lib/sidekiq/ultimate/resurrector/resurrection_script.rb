# frozen_string_literal: true

require "redis_prescription"
require "sidekiq/ultimate/configuration"
require "sidekiq/ultimate/resurrector/common_constants"

module Sidekiq
  module Ultimate
    module Resurrector
      # Lost jobs checker and resurrector
      class ResurrectionScript
        RESURRECT = RedisPrescription.new(File.read("#{__dir__}/lua_scripts/resurrect.lua"))
        private_constant :RESURRECT

        RESURRECT_WITH_COUNTER = RedisPrescription.new(File.read("#{__dir__}/lua_scripts/resurrect_with_counter.lua"))
        private_constant :RESURRECT_WITH_COUNTER

        class << self
          def call(redis, keys:)
            # redis-namespace can only namespace arguments of the lua script
            keys += [CommonConstants::MAIN_KEY] if enable_resurrection_counter_setting
            script.call(redis, :keys => keys)
          end

          private

          def script
            return @script if cache_setting? && defined?(@script)

            enable_resurrection_counter =
              if enable_resurrection_counter_setting.respond_to?(:call)
                enable_resurrection_counter_setting.call
              else
                enable_resurrection_counter_setting
              end

            script = enable_resurrection_counter ? RESURRECT_WITH_COUNTER : RESURRECT

            @script = script if cache_setting?
            script
          end

          def enable_resurrection_counter_setting
            Sidekiq::Ultimate::Configuration.instance.enable_resurrection_counter
          end

          def cache_setting?
            !enable_resurrection_counter_setting.respond_to?(:call)
          end
        end
      end
    end
  end
end
