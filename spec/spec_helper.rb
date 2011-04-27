$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'agi_config'))

@tropo_testing = true
%w(rubygems fakeweb eventmachine flexmock tropo-agitate lib/tropo yaml).each { |lib| require lib }
# em-spec/rspec Out for now since it is not Rspec 2.x compat

RSpec.configure do |config|
  config.mock_with :flexmock
end

# NOTE!
# TESTING REQUIRES JRUBY SINCE WE HAVE TO CREATE A JAVA HASHMAP IN THE TESTS
