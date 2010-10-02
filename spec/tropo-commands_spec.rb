require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "TropoAGItate::TropoCommands" do
  
  before(:all) do
    # These tests are all local unit tests
    FakeWeb.allow_net_connect = false
    
    # Register where we expect our YAML config file to live
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/tropo_agi_config/tropo_agi_config.yml", 
                         :body => File.open('tropo_agi_config/tropo_agi_config.yml').read)
                         
    # Register the hosted JSON file  
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/audio/asterisk_sounds/asterisk_sounds.json", 
                           :body => '{"tt-monkeys":"tt-monkeys.gsm"}')
    @tropo_agi = TropoAGItate.new(@current_call, CurrentApp.new)
    @tropo_commands = TropoAGItate::Commands.new(CurrentCall.new, @tropo_agi.tropo_agi_config)
  end
  
  it "should return the asterisk sound files" do
    @tropo_commands.asterisk_sound_files.should == { "tt-monkeys" => "tt-monkeys.gsm" }
  end
  
  it "should return a valid string on answer" do
    @tropo_commands.answer.should == "200 result=0\n"
  end
  
  it "should return a valid string on hangup" do
    @tropo_commands.hangup.should == "200 result=1\n"
  end
  
  it "should return a valid recognition on ask" do
    hash = { 'interpretation' => "94070", 'concept' => "zipcode", 'confidence' => "10.0", 'tag' => nil }
    options = { :command => "ask", :action => "exec", :args => { "timeout" => 3, "prompt" => "hi!"} }
    result = @tropo_commands.ask(options)
    elements = result.split('=')
    elements[0].should == '200 result'
    JSON.parse(elements[1]).should == hash
  end
  
  it "should return a valid agi response on playback" do
    options = { :action => "exec", :command => "playback", :args => ["Hello LRSC!"] }
    @tropo_commands.playback(options).should == "200 result=0\n"
  end
  
  it "should generate an error string if we pass an unknown command" do
    @tropo_commands.foobar.should == "200 result=-1\n"
    @tropo_commands.foobar('fooey').should == "200 result=-1\n"
  end
  
  it "should return a valid recognition on wait_for_digits" do
    options = { :action => "wait", :command => "for", :args => ["DIGIT \"-1\""] }
    @tropo_commands.wait_for_digits(options).should == "200 result=57\n"
  end
  
  it "should store and return a user variable" do
    result = @tropo_commands.user_vars({ :action => 'set', :args => ["\"foobar\" \"green\""]})
    result.should == "200 result=0\n"
    result = @tropo_commands.user_vars({ :action => 'get', :args => ["\"foobar\""]})
    result.should == "200 result=1 (green)\n"
    result = @tropo_commands.user_vars({ :action => 'get', :args => ["\"novar\""]})
    result.should == "200 result=-1\n"
  end
  
  it "should return a valid string when a dial is requested" do
    options = { :args => ["\"tel:+14153675082\"|\"\"|\"\""] }
    @tropo_commands.dial.should == "200 result=0\n"
  end
  
  it "should return a valid string when a file is requested" do
    options = { :args => ["\"hey there!\" \"1234567890*#\""] }
    @tropo_commands.file(options).should == "200 result=0\n"
  end
  
  it "should return a valid string when a meetme is requested" do
    options = { :args => ["\"1234\"|\"d\"|\"\""] }
    @tropo_commands.meetme(options).should == "200 result=0\n"
  end
end