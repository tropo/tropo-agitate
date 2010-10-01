$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'agi_config'))

@tropo_testing = true
%w(rubygems fakeweb eventmachine tropo-agi lib/tropo em-spec/rspec).each { |lib| require lib }

Spec::Runner.configure do |config|

end
