# For testing outside of Tropo we need to mock the global methods
# for logging and call management.
module Tropo
  def log(val)
    #STDERR.puts val
  end

  def show(val)
    log("====> #{val} <====")
  end

  def call(destination, options)
    raise "Unimplemented!"
  end

  class TropoEvent
    attr_accessor :name, :recordURI, :choice, :attempt, :value
    # @value is sometimes set to an instance of TropoCall
  end

  # Here for testing outside of Tropo, we need to mock the return on ask
  class AskResponse
    class Choice
      def concept
        'zipcode'
      end

      def confidence
        '10.0'
      end

      def interpretation
        '94070'
      end

      def tag
        nil
      end
    end

    attr_reader :choice

    def initialize
      @choice = Choice.new
    end

    def value
      '94070'
    end
  end

  # Here for testing outside of Tropo, so we mock the $currentCall object
  class CurrentCall
    attr_reader :value
    attr_reader :isActive
    attr_reader :state
    attr_reader :transferInfo

    def initialize
      @value = '94070'
      @headers = {}
      @isActive = true
      @state = 'RINGING'
    end

    def answer; @state ='ANSWERED'; end
    def ask(text, options); AskResponse.new; end
    def callerID; '4155551212'; end
    def calledID; '4045551234'; end
    def callerName; 'Jason Goecke'; end
    def call(text, options); 'call response: ' + text.inspect; p options; end
    def conference(text); 'conference reponse: ' + text.inspect; end
    def getHeader(header); @headers[header]; end

    def hangup
      @isActive = false
      @state    = 'DISCONNECTED'
    end

    def sessionId; '1234'; end
    def log(text); text; end
    def meetme(text, *rest); "meetme: #{text.inspect}, #{rest.inspect}"; end
    def say(text, options); 'say response: text'; options; end
    def setHeader(header, value); @headers[header] = value; end
    def sipgetheader(calleridname); calleridname; end
    def startCallRecording(uri, options={}); nil ; end
    def stopCallRecording; nil; end
    def state; 'RINGING'; end
    def record(uri, options); true; end

    def transfer(destinations, options)
      @transferInfo = {:destinations => destinations, :options => options}
      return TropoResult.new
    end
  end

  class TropoResult
    attr_accessor :name

    def initialize
      @name = 'transfer'
    end
  end

  # Here for testing outside of Tropo, so we mock the $currentApp object
  class CurrentApp
    class GetApp
      def getApp
        'Application[http://hosting.tropo.com/49767/www/tropo-agi.rb:cus] ver(1.0.45500)'
      end
    end

    def initialize(app_id = 49767)
      @app_id = app_id
    end

    def self.app
      GetApp.new
    end

    def baseDir
      @cnt = 0 if @cnt.nil?

      # This is only for testing JT!!!
      case @app_id
      when 49767
        # Keep returning Windows format
        'c:\tropo_app_home\49767'
      when 49768
        # Then return the Linux format for the last test
        '/tropo_app_home/49768'
      else
        raise "Unknown application id!"
      end
    end
  end

  class IncomingCall
    def getHeaderMap
      map = java.util.HashMap.new
      map.put "kermit", "green"
      map.put "bigbird", "yellow"
      map
    end
  end
end
# Make these methods global.
Object.send(:include, Tropo)
@tropo_testing = true
