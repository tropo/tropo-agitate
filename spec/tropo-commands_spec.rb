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
  end

  before(:each) do
    @tropo_agitate = TropoAGItate.new(@current_call, CurrentApp.new)
    @tropo_commands = TropoAGItate::Commands.new(CurrentCall.new, @tropo_agitate.tropo_agi_config)
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

  it "should return a valid recognition on ask when :args keys are strings" do
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
    expect { @tropo_commands.foobar }.to raise_error TropoAGItate::NonsenseCommand
    expect { @tropo_commands.foobar('fooey') }.to raise_error TropoAGItate::NonsenseCommand
  end

  it "should return a valid recognition on wait_for_digits" do
    options = { :action => "wait", :command => "for", :args => ["DIGIT \"-1\""] }
    @tropo_commands.wait_for_digits(options).should == "200 result=57\n"
  end

  it "should store and return a user variable" do
    result = @tropo_commands.channel_variable({ :action => 'set', :args => ["foobar", "green"]})
    result.should == "200 result=0\n"
    result = @tropo_commands.channel_variable({ :action => 'get', :args => ["foobar"]})
    result.should == "200 result=1 (green)\n"
    result = @tropo_commands.channel_variable({ :action => 'get', :args => ["novar"]})
    result.should == "200 result=0\n"
  end

  it "should return a valid string when a dial is requested" do
    options = ["tel:+14153675082","",""]
    @tropo_commands.dial(*options).should == "200 result=0\n"
  end

  it "should return a valid string when a file is requested" do
    options = ['hey there!', '1234567890*#']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
  end

  it "should return a valid string when a meetme is requested" do
    options = ['1234', 'd', '']
    @tropo_commands.meetme(*options).should == "200 result=0\n"
  end

  it "should return a valid string when we request a record" do
    options = { :args => ['http://tropo-audiofiles-to-s3.heroku.com/post_audio_to_s3?filename=voicemail', 'mp3', '#' '120000', '0', 'BEEP', 's=5'] }
    @tropo_commands.agi_record(options).should == "200 result=0 endpos=1000\n"
  end

  it "should return a valid string when we reqeust a monitor/mixmonitor" do
    options = ['http://localhost/save_recording']
    @tropo_commands.monitor(*options).should == "200 result=0\n"
    @tropo_commands.mixmonitor(*options).should == "200 result=0\n"
  end

  it "should return a valid string when we reqeust a startcallrecording" do
    options = { :args => { "uri"                 => "http://localhost/post_audio_to_s3?filename=voicemail.mp3",
                           "method"              => "POST",
                           "format"              => "mp3",
                           "transcriptionOutURI" => "mailto:jsgoecke@voxeo.com"} }
    @tropo_commands.startcallrecording(options).should == "200 result=0\n"
  end

  it "should return a valid string when we request a stopcallrecording" do
    @tropo_commands.stopcallrecording.should == "200 result=0\n"
    @tropo_commands.monitor_stop.should == "200 result=0\n"
    @tropo_commands.mixmonitor_stop.should == "200 result=0\n"
  end

  it "should return a valid string when a voice is set" do
    options = { :args => ["simon"] }
    @tropo_commands.voice(*options).should == "200 result=0\n"
  end

  it "should return a valid string when a recognizer is set" do
    options = { :args => ["en-us"] }
    @tropo_commands.recognizer(*options).should == "200 result=0\n"
  end
  
  it "should support a stream file without escape digits" do
    options = ['hey there!']
    @tropo_commands.file(*options).should == "200 result=0 endpos=1000\n"
  end
  
  it "should support a stream file with escape digits" do
    options = ['hey there!', '1234567890#']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
    
    options = ['hey there!', '1234567890#*']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
    
    options = ['hey there!', '1234567890*']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
    
    options = ['hey there!', '1234']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
    
    options = ['hey there!', '#']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"

    options = ['hey there!', '*']
    @tropo_commands.file(*options).should == "200 result=57 endpos=1000\n"
  end
end
