# frozen_string_literal: true

source "https://rubygems.org"
ruby RUBY_VERSION

gem "rake"
gem "rspec"
gem "rubocop", "~> 0.52.0", :require => false

group :development do
  gem "guard",         :require => false
  gem "guard-rspec",   :require => false
  gem "guard-rubocop", :require => false
  gem "pry",           :require => false
end

group :test do
  gem "codecov",    :require => false
  gem "simplecov",  :require => false
end

group :doc do
  gem "redcarpet"
  gem "yard"
end

# Specify your gem's dependencies in redis-prescription.gemspec
gemspec
