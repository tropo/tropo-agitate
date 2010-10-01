# ALL OF THESE TESTS ARE PENDING, HAVE SOME STRANGENESS WITH EM AND RSPEC

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "TropoAGI" do
  before(:all) do
    # These tests are all local unit tests
    FakeWeb.allow_net_connect = false
    
    # Register the hosted JSON file  
    FakeWeb.register_uri(:get, "http://hosting.tropo.com/49767/www/audio/asterisk_sounds/asterisk_sounds.json", 
                         :body => '{"tt-monkeys":"tt-monkeys.gsm"}')
                           
    @current_call = CurrentCall.new
    @tropo_agi = TropoAGI.new(@current_call, AGI_URI_FOR_LOCAL_TEST, ASTERISK_SOUNDS)
  end
  
  it "should execute a series of commands sent by an AGI Server" do
    module AgiServer
      
      def post_init
        @commands = [ { :command => 'Initial Session', :response => @initial_message },
                      { :command => "ANSWER\n", :response => "200 result=0\n" },
                      { :command => "EXEC playback \"Hello LRSC!\"\n", :response => "200 result=0\n" },
                      { :command => 'EXEC MeetMe "1234","d",""' + "\n", :response => "200 result=0\n" },
                      { :command => 'SET CALLERID "9095551234"' + "\n", :response => "200 result=0\n" },
                      { :command => 'SET CALLERIDNAME "John Denver"' + "\n", :response => "200 result=0\n" },
                      { :command => 'GET VARIABLE "CALLERIDNAME"' + "\n", :response => "200 result=1 (John Denver)" },
                      { :command => 'SET VARIABLE FOOBAR "green"' + "\n", :response => "200 result=0\n" },
                      { :command => 'GET VARIABLE "FOOBAR"' + "\n", :response => "200 result=1 (green)" },
                      { :command => 'EXEC monitor "{\"method\":\"POST\",\"uri\":\"http://localhost\"}"' + "\n", :response => "200 result=0\n" },
                      { :command => 'EXEC mixmonitor "{\"method\":\"POST\",\"uri\":\"http://localhost\"}"' + "\n", :response => "200 result=0\n" },
                      { :command => 'EXEC sipgetheader "CALLERIDNAME"' + "\n", :response => "200 result=0\n" },
                      { :command => 'HANGUP' + "\n", :response => "200 result=0\n" } ]
        @cnt = 1
        @responses = []
      end

      def receive_data data
        p data
        case data 
        when "commands\n", "commands\r\n"
          p @commands
          send_data @commands.to_json + "\n"
        when "responses\n", "responses\r\n"
          send_data @responses.to_json + "\n"
        else
          @responses << data
          send_data @commands[@cnt][:command]
          @cnt += 1
        end
      end

      def unbind
        # Nothing here for now
      end
    end

    agi_server_thread = Thread.new do
      EventMachine::run {
        EventMachine::start_server "127.0.0.1", 4573, AgiServer
      }
    end
    
    @tropo_agi.run
    puts 'blah blah blah blah'
    
    @commands, @results = nil, nil
    tcp_client = TCPSocket.new("127.0.0.1", 4573)
    tcp_client.write("commands\n")
    @commands = JSON.parse(tcp_client.gets.rstrip)
    tcp_client.write("responses\n")
    @results = JSON.parse(tcp_client.gets.rstrip)
    tcp_client.close
    
    @commands.each_with_index do |command, index|
      command['response'].should == @results[index]
    end
  end
end