# frozen_string_literal: true

require "concurrent/timer_task"

module Sidekiq
  module Ultimate
    class EmptyQueues
      # Timer task that periodically refreshes empty queues. Also adds jitter to the execution interval.
      class RefreshTimerTask
        TASK_CLASS = Class.new(Concurrent::TimerTask)

        RANDOM_OFFSET_RATIO = 0.1

        class << self
          def setup!(empty_queues_class)
            task = TASK_CLASS.new({
              :run_now            => true,
              :execution_interval => execution_interval
            }) { empty_queues_class.instance.refresh! }
            task.execute
          end

          private

          # Returns execution interval with jitter.
          # Jitter is +- RANDOM_OFFSET_RATION from the original value.
          def execution_interval
            execution_interval = Sidekiq::Ultimate::Configuration.instance.empty_queues_refresh_interval_sec

            jitter_ratio = (rand(0..RANDOM_OFFSET_RATIO) * 2) - RANDOM_OFFSET_RATIO
            execution_interval + (jitter_ratio * execution_interval)
          end
        end
      end
    end
  end
end
