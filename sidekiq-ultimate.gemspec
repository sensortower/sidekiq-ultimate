# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sidekiq/ultimate/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-ultimate"
  spec.version       = Sidekiq::Ultimate::VERSION
  spec.authors       = ["Alexey Zapparov"]
  spec.email         = ["ixti@member.fsf.org"]

  spec.summary       = "Sidekiq ultimate experience."
  spec.description   = "Sidekiq ultimate experience."

  spec.homepage      = "https://github.com/sensortower/sidekiq-ultimate"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "concurrent-ruby",    "~> 1.0"
  spec.add_runtime_dependency "redis-lockers",      "~> 1.1"
  spec.add_runtime_dependency "redis-prescription", "~> 1.0"
  spec.add_runtime_dependency "sidekiq",            "~> 5.0"

  # temporary couple this with sidekiq-throttled until it will be merged into
  # this gem instead.
  spec.add_runtime_dependency "sidekiq-throttled", "~> 0.8.2"

  spec.add_development_dependency "bundler", "~> 1.16"

  spec.required_ruby_version = "~> 2.3"
end