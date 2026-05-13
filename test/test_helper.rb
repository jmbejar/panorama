ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Disabled: the panorama workspace lives under tmp/panorama_projects/:id and
    # SQLite reuses primary keys across rolled-back transactions, so parallel
    # workers race on the same directory paths. Tests are fast enough serially.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
