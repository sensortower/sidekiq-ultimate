# frozen_string_literal: true

require "concurrent/timer_task"
require "sidekiq/ultimate/interval_with_jitter"

module Sidekiq
  module Ultimate
    class EmptyQueues
      # Timer task that periodically refreshes empty queues. Also adds jitter to the execution interval.
      class RefreshTimerTask
        TASK_CLASS = Class.new(Concurrent::TimerTask)

        class << self
          def setup!(empty_queues_class)
            interval = Sidekiq::Ultimate::Configuration.instance.empty_queues_cache_refresh_interval_sec
            task = TASK_CLASS.new({
              :run_now            => true,
              :execution_interval => Sidekiq::Ultimate::IntervalWithJitter.call(interval)
            }) { empty_queues_class.instance.refresh! }
            task.execute
          end
        end
      end
    end
  end
end
