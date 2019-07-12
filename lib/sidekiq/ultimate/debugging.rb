# frozen_string_literal: true

module Sidekiq
  module Ultimate
    module Debugging
      private

      def debug!
        return unless ENV.key? "DEBUG_SIDEKIQ_ULTIMATE"
        Sidekiq.logger.debug { "[#{self.class}] #{yield}" }
      end
    end
  end
end
