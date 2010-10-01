# Here for testing outside of Tropo, so we mock the $currentCall object
class CurrentCall
  attr_reader :value
  attr_reader :isActive
  
  def initialize
    @value = '94070'
    @headers = {}
    @isActive = true
  end
  
  def answer; 'answer response: answered'; end
  def ask(text, options); 'ask reponse: ' + text; self; end
  def callerID; '4155551212'; end
  def callerName; 'Jason Goecke'; end
  def call(text, options); 'call response: ' + text.inspect; p options; end
  def conference(text); 'conference reponse: ' + text.inspect; end
  def getHeader(header); @headers[header]; end
  def hangup; @isActive = false; end
  def id; '1234'; end
  def log(text); text; end
  def meetme(text, *rest); "meetme: #{text.inspect}, #{rest.inspect}"; end
  def say(text, options); 'say response: text'; options; end
  def setHeader(header, value); @headers[header] = value; end
  def sipgetheader(calleridname); calleridname; end
  def startCallRecording(uri, options); uri + options.inspect; end
  def state; 'RINGING'; end
  def transfer(foo, bar); true; end
end

# Here for testing outside of Tropo, so we mock the $currentApp object
class CurrentApp
  class GetApp
    def getApp
      'Application[http://hosting.tropo.com/49767/www/tropo-agi.rb:cus] ver(1.0.45500)'
    end
  end
  
  def self.app
    GetApp.new
  end
  
  def baseDir
    'c:\tropo_app_home\49767'
  end
end

