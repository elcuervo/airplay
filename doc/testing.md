# Testing

Now there are two types of tests: Regular unit tests and integration tests.
Thanks to the magic of the internet and a raspberry pi there are integration
tests with a real Apple TV that is currently accessible.

![Block TV](doc/img/block_tv.jpg)

The Apple TV is password protected to avoid issues with the tests but is
configured in Travis CI. For that reason you won't be able to run those tests if
you don't have an Apple TV.

Run unit tests with: `rake test:unit` and integration ones with: `rake test:integration`
You can run all of them together with: `rake test:all`
