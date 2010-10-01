$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'agi_config'))

@tropo_testing = true
%w(rubygems fakeweb eventmachine tropo-agitate lib/tropo em-spec/rspec yaml).each { |lib| require lib }

Spec::Runner.configure do |config|

end

# NOTE!
# TESTING REQUIRES JRUBY SINCE WE HAVE TO CREATE A JAVA HASHMAP IN THE TESTS