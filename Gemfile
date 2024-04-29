# frozen_string_literal: true

source "https://rubygems.org"
ruby RUBY_VERSION

gem "appraisal"
gem "rake"
gem "rspec"
gem "rubocop", "~> 1.50.2", :require => false
gem "rubocop-performance", "~> 1.17.1", :require => false
gem "rubocop-rake", "~> 0.6.0", :require => false
gem "rubocop-rspec", "~> 2.20.0", :require => false

group :development do
  gem "guard",         :require => false
  gem "guard-rspec",   :require => false
  gem "guard-rubocop", :require => false
  gem "pry",           :require => false
end

group :test do
  gem "simplecov",  :require => false
end

gemspec
