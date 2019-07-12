# frozen_string_literal: true

module Sidekiq
  module Ultimate
    module Debugging
      private

      def debug!
        Sidekiq.logger.debug { "[#{self.class}] #{yield}" }
      end
    end
  end
end
