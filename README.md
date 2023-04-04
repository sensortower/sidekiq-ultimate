# Sidekiq::Ultimate

Sidekiq ultimate experience.

---

**WARNING**

This ia an alpha/preview software. Lots of changes will be made and eventually
it will overtake [sidekiq-throttled][] and will become truly ultimate sidekiq
extension one will need. :D

---


## Installation

Add this line to your application's Gemfile:

```ruby
gem "sidekiq-ultimate", ">= 0.0.1.alpha"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-ultimate


## Usage

Add somewhere in your app's bootstrap (e.g. `config/initializers/sidekiq.rb` if
you are using Rails):

``` ruby
require "sidekiq/ultimate"
Sidekiq::Ultimate.setup!
```

## Configuration

Resurrection events can be additionally logged by providing `on_resurrection` handler:

```ruby
Sidekiq::Ultimate.setup! do |config|
  config.on_resurrection = ->(queue_name, jobs_count) do
    puts "Resurrected #{jobs_count} jobs from #{queue_name}"
  end
end
```

---

**NOTICE**

Throttling is brought by [sidekiq-throttled][] and it's automatically set up
by the command above - don't run `Sidekiq::Throttled.setup!` yourself.

Thus look up it's README for throttling configuration details.

---


## Supported Ruby Versions

This library aims to support and is [tested against][travis-ci] the following
Ruby and Redis client versions:

* Ruby
  * 2.3.x
  * 2.4.x
  * 2.5.x
  * 2.6.x
  * 2.7.x

* [redis-rb](https://github.com/redis/redis-rb)
  * 4.x

* [redis-namespace](https://github.com/resque/redis-namespace)
  * 1.6


If something doesn't work on one of these versions, it's a bug.

This library may inadvertently work (or seem to work) on other Ruby versions,
however support will only be provided for the versions listed above.

If you would like this library to support another Ruby version or
implementation, you may volunteer to be a maintainer. Being a maintainer
entails making sure all tests run and pass on that implementation. When
something breaks on your implementation, you will be responsible for providing
patches in a timely fashion. If critical issues for a particular implementation
exist at the time of a major release, support for that Ruby version may be
dropped.


## Development

After checking out the repo, run `bundle install` to install dependencies.
Then, run `bundle exec rake spec` to run the tests with ruby-rb client.

To install this gem onto your local machine, run `bundle exec rake install`.
To release a new version, update the version number in `version.rb`, and then
run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to [rubygems.org][].


## Contributing

* Fork sidekiq-ultimate on GitHub
* Make your changes
* Ensure all tests pass (`bundle exec rake`)
* Send a pull request
* If we like them we'll merge them
* If we've accepted a patch, feel free to ask for commit access!


## Copyright

Copyright (c) 2018-23 SensorTower Inc.<br>
See [LICENSE.md][] for further details.


[travis.ci]: http://travis-ci.org/sensortower/sidekiq-ultimate
[rubygems.org]: https://rubygems.org
[LICENSE.md]: https://github.com/sensortower/sidekiq-ultimate/blob/master/LICENSE.txt
[sidekiq-throttled]: http://travis-ci.org/sensortower/sidekiq-throttled
