# frozen_string_literal: true

source "https://rubygems.org"
ruby RUBY_VERSION

gem "appraisal"
gem "rake"
gem "rspec"
gem "rubocop", "~> 1.49.0", :require => false
gem "rubocop-performance", :require => false
gem "rubocop-rake", :require => false
gem "rubocop-rspec", :require => false

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

gemspec
