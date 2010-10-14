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
                           
    @current_call = CurrentCall.new
    $incomingCall = IncomingCall.new
    @tropo_agitate = TropoAGItate.new(@current_call, CurrentApp.new)
  end
  
  it "should create a TropoAGItate object" do
    @tropo_agitate.instance_of?(TropoAGItate).should == true
  end
  
  it "should create a properly formatted initial message" do
    agi_uri  = URI.parse @tropo_agitate.tropo_agi_config['agi']['uri_for_local_tests']
    message  = @tropo_agitate.initial_message(agi_uri.host, agi_uri.port, agi_uri.path[1..-1])
    @initial_message = <<-MSG
agi_network: yes
agi_network_script: #{agi_uri.path[1..-1]}
agi_request: agi://#{agi_uri.host}:#{agi_uri.port}#{agi_uri.path}
agi_channel: TROPO/#{@current_call.id}
agi_language: en
agi_type: TROPO
agi_uniqueid: #{@current_call.id}
agi_version: tropo-agi-0.1.0
agi_callerid: #{@current_call.callerID}
agi_calleridname: #{@current_call.callerName}
agi_callingpres: 0
agi_callingani2: 0
agi_callington: 0
agi_callingtns: 0
agi_dnid: 1000
agi_rdnis: unknown
agi_context: #{agi_uri.path[1..-1]}
agi_extension: 1
agi_priority: 1
agi_enhanced: 0.0
agi_accountcode: 
agi_threadid: #{@current_call.id}
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
  
  it "should execute the command" do
    command = @tropo_agitate.execute_command('EXEC MeetMe "1234","d",""')
    command.should == "200 result=0\n"

    command = @tropo_agitate.execute_command('SET CALLERID "9095551234"')
    command.should == "200 result=0\n"
    
    command = @tropo_agitate.execute_command('SET CALLERIDNAME "John Denver"')
    command.should == "200 result=0\n"
    
    command = @tropo_agitate.execute_command('GET VARIABLE "CALLERIDNAME"')
    command.should == "200 result=1 (John Denver)\n"
    
    command = @tropo_agitate.execute_command('SET VARIABLE FOOBAR "green"')
    command.should == "200 result=0\n"
    
    command = @tropo_agitate.execute_command('GET VARIABLE "FOOBAR"')
    command.should == "200 result=1 (green)\n"
    

    command = @tropo_agitate.execute_command("EXEC monitor #{{ 'method' => 'POST', 'uri' => 'http://localhost' }.to_json}")
    command.should == "200 result=0\n"
    
    command = @tropo_agitate.execute_command('EXEC voice "simon"')
    command.should == "200 result=0\n"
    
    command = @tropo_agitate.execute_command('EXEC recognizer "en-us"')
    command.should == "200 result=0\n"
  end
end