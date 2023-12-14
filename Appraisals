# frozen_string_literal: true

REDIS_VERSIONS = %w[4.2.0 4.8.0].freeze
SIDEKIQ_VERSIONS = %w[6.2.0].freeze

version_combinations = REDIS_VERSIONS.product(SIDEKIQ_VERSIONS)

version_combinations.each do |redis_version, sidekiq_version|
  appraise "redis_#{redis_version}_sidekiq_#{sidekiq_version}" do
    gem "redis", "~> #{redis_version}"
    gem "sidekiq", "~> #{sidekiq_version}"
  end
end
