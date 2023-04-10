# frozen_string_literal: true

require "sidekiq/ultimate/resurrector/common_constants"

module Sidekiq
  module Ultimate
    module Resurrector
      # Allows to get the count of times the job was resurrected
      module Count
        class << self
          # @param job_id [String] job id
          # @return [Integer] count of times the job was resurrected
          def read(job_id:)
            Sidekiq.redis do |redis|
              redis.get("#{CommonConstants::MAIN_KEY}:counter:jid:#{job_id}").to_i
            end
          end
        end
      end
    end
  end
end
