require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "TropoAGItate" do

  before(:all) do
    # These tests are all local unit tests
    FakeWeb.allow_net_connect = false

    # Register where we expect our YAML config file to live
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/tropo_agi_config/tropo_agi_config.yml",
                         :body => File.open('tropo_agi_config/tropo_agi_config.yml').read)

    # Register the hosted JSON file
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/audio/asterisk_sounds/asterisk_sounds.json",
                         :body => '{"tt-monkeys":"tt-monkeys.gsm"}')

  end

  before(:each) do
    $currentCall   = CurrentCall.new
    $currentApp    = CurrentApp.new
    $incomingCall  = IncomingCall.new
    $destination   = nil
    $caller_id     = nil
    $timeout       = nil
    $network       = nil
    $channel       = nil
    @tropo_agitate = agitate_factory
  end

  it "should create a TropoAGItate object" do
    @tropo_agitate.instance_of?(TropoAGItate).should == true
  end

  describe 'Hash' do
    it 'should symbolize our keys in a hash' do
      h = { 'foo' => 'yes', 'bar' => 'no' }
      h.symbolize_keys!
      h.should == { :foo => 'yes', :bar => 'no' }
    end
  end

  it "should create a properly formatted initial message" do
    agi_uri  = URI.parse @tropo_agitate.tropo_agi_config['agi']['uri_for_local_tests']
    message  = @tropo_agitate.initial_message(agi_uri.host, agi_uri.port, agi_uri.path[1..-1])
    @initial_message = <<-MSG
agi_network: yes
agi_network_script: #{agi_uri.path[1..-1]}
agi_request: agi://#{agi_uri.host}:#{agi_uri.port}#{agi_uri.path}
agi_channel: TROPO/#{$currentCall.sessionId}
agi_language: en
agi_type: TROPO
agi_uniqueid: #{$currentCall.sessionId}
agi_version: tropo-agi-0.1.0
agi_callerid: #{$currentCall.callerID}
agi_calleridname: #{$currentCall.callerName}
agi_callingpres: 0
agi_callingani2: 0
agi_callington: 0
agi_callingtns: 0
agi_dnid: #{$currentCall.calledID}
agi_rdnis: unknown
agi_context: #{agi_uri.path[1..-1]}
agi_extension: s
agi_priority: 1
agi_enhanced: 0.0
agi_accountcode: 0
agi_threadid: #{Thread.current.to_s}
tropo_headers: {\"kermit\":\"green\",\"bigbird\":\"yellow\"}

MSG
    message.should == @initial_message
  end

  it "should parse arguments stripping quotes" do
    result = @tropo_agitate.parse_args('"Hello LSRC!"')
    result[0].should == "Hello LSRC!"

    result = @tropo_agitate.parse_args('"{"prompt":"hi!","timeout":3}"')
    result.should == { "timeout" => 3, "prompt" => "hi!"}

    result = @tropo_agitate.parse_args('"1234","d",""')

    result[0].should == '1234'
    result[1].should == 'd'
    result[3].should == nil
  end

  it "should strip quotes from a string" do
    @tropo_agitate.strip_quotes('"foobar"').should == 'foobar'
  end

  it "should handle commas in non JSON args" do
    command = @tropo_agitate.parse_command('EXEC playback "Hello, LRSC!"')
    command.should == { :action => "exec", :command => "playback", :args => ["Hello, LRSC!"] }
  end

  it "should extract the appropriate commands from AGI" do
    command = @tropo_agitate.parse_command('ANSWER')
    command.should == { :action => "answer" }

    command = @tropo_agitate.parse_command('HANGUP')
    command.should == { :action => "hangup" }

    command = @tropo_agitate.parse_command('EXEC playback "Hello LRSC!"')
    command.should == { :action => "exec", :command => "playback", :args => ["Hello LRSC!"] }

    command = @tropo_agitate.parse_command('EXEC ask "{"prompt":"hi!","timeout":3}"')
    command.should == { :command => "ask", :action => "exec", :args => { "timeout" => 3, "prompt" => "hi!"} }

    command = @tropo_agitate.parse_command('EXEC Dial "sip:jsgoecke@yahoo.com","",""')
    command.should == { :command => "dial", :action => "exec", :args => ["sip:jsgoecke@yahoo.com", "", ""] }

    command = @tropo_agitate.parse_command('EXEC AMD')
    command.should == { :command => "amd", :action => "exec" }

    command = @tropo_agitate.parse_command('EXEC MeetMe "1234","d",""')
    command.should == { :command => "meetme", :action => "exec", :args => ["1234", "d", ""] }

    command = @tropo_agitate.parse_command('SET CALLERID "9095551234"')
    command.should == { :command => "callerid", :action => "set", :args => ["9095551234"] }

    command = @tropo_agitate.parse_command('SET MYVAR "foobar"')
    command.should == { :command => "myvar", :action => "set", :args => ["foobar"] }

    command = @tropo_agitate.parse_command('GET VARIABLE "myvar"')
    command.should == { :command => "variable", :action => "get", :args => ["myvar"] }

    command = @tropo_agitate.parse_command('EXEC monitor "{"method":"POST","uri":"http://localhost"}"')
    command.should == { :command => "monitor", :action => "exec", :args => { 'method' => 'POST', 'uri' => 'http://localhost' } }

    command = @tropo_agitate.parse_command('EXEC mixmonitor "{"method":"POST","uri":"http://localhost"}"')
    command.should == { :command => "mixmonitor", :action => "exec", :args => { 'method' => 'POST', 'uri' => 'http://localhost' } }
  end

  it "should set DIALSTATUS after placing a call" do
    dest = "sip:+14045551234"
    @tropo_agitate.execute_command("EXEC Dial \"#{dest}\",\"20\",\"\"")
    command = @tropo_agitate.execute_command('GET VARIABLE DIALSTATUS')
    command.should == "200 result=1 (ANSWER)\n"
    $currentCall.transferInfo[:destinations].should == [dest]
  end

  it "should set the dial timeout correctly" do
    timeout = 45
    @tropo_agitate.execute_command("EXEC Dial \"sip:+14045551234\",\"#{timeout}\",\"\"")
    $currentCall.transferInfo[:options][:timeout].should == timeout
  end

  it "should properly detect an answering machine" do
    flexmock($currentCall).should_receive(:record).and_return do |*args|
      # Simulate a long recording, indicating that silence is not received for more than 4 seconds
      sleep 5
    end

    @tropo_agitate.execute_command("EXEC AMD")
    amdstatus = @tropo_agitate.execute_command('GET VARIABLE AMDSTATUS')
    amdcause  = @tropo_agitate.execute_command('GET VARIABLE AMDCAUSE')
    amdstatus.should == "200 result=1 (MACHINE)\n"
    amdcause.should  == "200 result=1 (TOOLONG-5)\n"
  end

  it "should properly detect a human" do
    @tropo_agitate.execute_command("EXEC AMD")
    amdstatus = @tropo_agitate.execute_command('GET VARIABLE AMDSTATUS')
    amdcause  = @tropo_agitate.execute_command('GET VARIABLE AMDCAUSE')
    amdstatus.should == "200 result=1 (HUMAN)\n"
    amdcause.should  == "200 result=1 (HUMAN-1-1)\n"
  end


  it "should set the callerdID correctly" do
    callerid = "4045551234"
    @tropo_agitate.execute_command("SET VARIABLE CALLERID(num) #{callerid}")
    @tropo_agitate.execute_command("EXEC Dial \"sip:+14045551234\",\"30\",\"\"")
    $currentCall.transferInfo[:options][:callerID].should == callerid
  end

  it "should execute the command" do
    command = @tropo_agitate.execute_command('EXEC MeetMe "1234","d",""')
    command.should == "200 result=0\n"

    command = @tropo_agitate.execute_command("EXEC monitor #{{ 'method' => 'POST', 'uri' => 'http://localhost' }.to_json}")
    command.should == "200 result=0\n"

    command = @tropo_agitate.execute_command('EXEC voice "simon"')
    command.should == "200 result=0\n"

    command = @tropo_agitate.execute_command('EXEC recognizer "en-us"')
    command.should == "200 result=0\n"
  end

  it "should handle magic channel variables properly" do
    number = "9095551234"
    name = "John Denver"

    command = @tropo_agitate.execute_command("SET CALLERID \"<#{number}>\"")
    command.should == "200 result=0\n"
    command = @tropo_agitate.execute_command('GET VARIABLE CALLERID(num)')
    command.should == "200 result=1 (#{number})\n"

    command = @tropo_agitate.execute_command("SET VARIABLE CALLERIDNAME \"#{name}\"")
    command.should == "200 result=0\n"
    command = @tropo_agitate.execute_command('GET VARIABLE "CALLERIDNAME"')
    command.should == "200 result=1 (John Denver)\n"
    command = @tropo_agitate.execute_command('GET VARIABLE "CALLERID(name)"')
    command.should == "200 result=1 (John Denver)\n"

    command = @tropo_agitate.execute_command('GET VARIABLE "CALLERID(all)"')
    command.should == "200 result=1 (\"#{name}\" <#{number}>)\n"

    command = @tropo_agitate.execute_command('SET VARIABLE FOOBAR "green"')
    command.should == "200 result=0\n"
    command = @tropo_agitate.execute_command('GET VARIABLE "FOOBAR"')
    command.should == "200 result=1 (green)\n"
  end

  it "should execute the command as Asterisk-Java would pass" do
    command = @tropo_agitate.execute_command('EXEC "playback" "tt-monkeys"')
    command.should == "200 result=0\n"

    command = @tropo_agitate.execute_command('STREAM FILE "tt-monkeys" "1234567890*#"')
    command.should == "200 result=57 endpos=0\n"
  end

  it "should handle the STREAM FILE requests" do
    command = @tropo_agitate.execute_command('STREAM FILE tt-monkeys 1234567890*#')
    command.should == "200 result=57 endpos=0\n"

    command = @tropo_agitate.execute_command('STREAM FILE tt-monkeys')
    command.should == "200 result=0 endpos=0\n"

    command = @tropo_agitate.execute_command('STREAM STREAMFILE tt-monkeys 1234567890*#')
    command.should == "200 result=57 endpos=0\n"
  end

  it "should return the account data from a directory lookup on Windows" do
    TropoAGItate.new($currentCall, CurrentApp.new(49767)).fetch_account_data[1].should == '49767'
  end

  it "should return the account data from a directory lookup on Linux" do
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49768/www/tropo_agi_config/tropo_agi_config.yml",
                         :body => File.open('tropo_agi_config/tropo_agi_config.yml').read)
    TropoAGItate.new($currentCall, CurrentApp.new(49768)).fetch_account_data[1].should == '49768'
  end

  it "should execute a read" do
    command = @tropo_agitate.execute_command('EXEC READ pin,tt monkeys,5,,3,10')
    command.should == "200 result=0\n"
  end

  it 'should properly dial an outbound call when invoked via REST' do
    # Simulate parameters passed as query string variables
    $currentCall = nil
    $destination = '14045556789'
    $caller_id   = '14155551234'
    $timeout     = '47'

    options = {:callerID => $caller_id,
               :timeout => $timeout.to_i,
               :channel => 'voice',
               :network => 'SMS'}

    # Test the origination
    response = TropoEvent.new
    response.name = 'answer'
    flexmock(self).should_receive(:call).with("tel:+#{$destination}", options).and_return response
    @tropo_agitate = agitate_factory
  end

  it 'should send a "failed" call when dial results in an error' do
    # Simulate parameters passed as query string variables
    $currentCall = nil
    $destination = 'XXX'
    $caller_id   = '14155551234'
    $timeout     = '47'

    options = {:callerID => $caller_id,
               :timeout => $timeout.to_i,
               :channel => 'voice',
               :network => 'SMS'}

    # Test the origination
    response = TropoEvent.new
    response.name = 'error'
    flexmock(self).should_receive(:call).with("tel:+#{$destination}", options).and_return response
    @tropo_agitate = agitate_factory

    agi_environment = @tropo_agitate.initial_message('127.0.0.1', 1, 'example').split("\n")
    agi_environment.grep(/agi_extension/)[0].match(/^agi_extension: (.*)$/)[1].should == 'failed'

    @tropo_agitate.execute_command('GET VARIABLE REASON').should == "200 result=1 (8)\n"
  end
end
