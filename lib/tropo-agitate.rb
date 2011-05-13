%w(rubygems yaml socket json net/http uri).each { |lib| require lib }
#####
# This Ruby Script Emulates the Asterisk Gateway Interface (AGI)
# VERSION = '0.1.9'
#####

# We patch the Hash class to symbolize our keys
class Hash
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end

  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end
end

#########
# @author Jason Goecke
class TropoAGItate
  attr_accessor :agi_uri, :agi_exten, :commands

  module Helpers
    ##
    # Strips the quotes from a string
    #
    # @param [String] the string to remove the strings from
    #
    # @return [String] the string with the quotes removed
    def strip_quotes(text)
      text.sub(/^"/, '').sub(/"$/, '')
    end

    ##
    # Formats the output to the log for consistency
    #
    # @param [String] string to output to the log
    # @return nil
    def show(str)
      log "====> #{str} <===="
    end

    ##
    # Provides the current method's name
    #
    # @return [String] the name of the current method
    def this_method
      caller[0]
      # caller[0][/`([^']*)'/, 1]
    end

  end

  include Helpers
  class Commands
    attr_accessor :chanvars

    include Helpers

    ##
    # Creates an instance of Command
    #
    # @param [Object] the currentCall object from Tropo Scripting
    # @param [Hash] contains the configuration of the files available as Asterisk Sounds
    #
    # @return [Object] an instance of Command
    def initialize(current_call, tropo_agi_config)
      @current_call     = current_call
      @tropo_agi_config = tropo_agi_config
      @agi_response     = "200 result="
      @tropo_voice      = @tropo_agi_config['tropo']['voice']
      @tropo_recognizer = @tropo_agi_config['tropo']['recognizer']

      # Used to store user request values for SET/GET VARIABLE commands of Asterisk
      # May also be passed in as a JSON string from the Tropo Session API
      if $user_vars
        @chanvars = TropoAGItate::MagicChannelVariables.new JSON.parse $user_vars
      else
        @chanvars = TropoAGItate::MagicChannelVariables.new
      end
      @asterisk_sound_files = asterisk_sound_files if @tropo_agi_config['asterisk']['sounds']['enabled']
    end

    ##
    # Initiates an answer to the Tropo call object based on an answer request via AGI
    # AGI: http://www.voip-info.org/wiki/view/answer
    # Tropo: https://www.tropo.com/docs/scripting/answer.htm
    #
    # @return [String] the response in AGI raw form
    def answer
      if @current_call.state == 'RINGING'
        @current_call.answer
      else
        show "Warning - invalid call state to invoke an answer: #{@current_call.state.inspect}"
      end
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Initiates an ask to the Tropo call object
    # Tropo: https://www.tropo.com/docs/scripting/ask.htm
    #
    # @param [Hash] the options to be used on the ask method
    #
    # @return [String] the response in AGI raw form
    def ask(options={})
      check_state

      options[:args][:recognizer] = @tropo_recognizer if options[:args]['recognizer'].nil?
      options[:args][:voice] = @tropo_voice if options[:args]['voice'].nil?

      # Check for Asterisk sounds
      asterisk_sound_url = fetch_asterisk_sound(options[:args]['prompt'])
      if asterisk_sound_url
        prompt = asterisk_sound_url
      else
        prompt = options[:args]['prompt']
      end

      response = @current_call.ask prompt, options[:args].symbolize_keys!
      if response.value == 'NO_SPEECH' || response.value == 'NO_MATCH'
        result = { :interpretation => response.value }
      else
        result = { :concept        => response.choice.concept,
                   :confidence     => response.choice.confidence,
                   :interpretation => response.choice.interpretation,
                   :tag            => response.choice.tag }
      end
      @agi_response + result.to_json + "\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Sets the callerid params in Tropo
    #
    # @param [Hash] the options to be used when setting callerid/calleridname
    #
    # @return [String] the response in AGI raw form
    def callerid(options={})
      @chanvars['CALLERID'] = options[:args][0]
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Initiates a transfer on Tropo which corresopnds as a dial over AGI
    # AGI: http://www.voip-info.org/wiki/view/Asterisk+cmd+Dial
    # Tropo: https://www.tropo.com/docs/scripting/transfer.htm
    #
    # @param [Hash] the options used to place the dial
    #
    # @return [String] the response in AGI raw form
    def dial(options={})
      check_state
      args = options.delete(:args) || {}
      destinations = parse_destinations(args.shift.split('&'))
      options = {}

      # Convert Asterisk app_dial inputs to Tropo syntax
      options[:timeout]  = args.shift.to_i if args.count

      # TODO: We may want to provide some compatibility with Asterisk dial flags
      # like m for MOH, A() to play announcement to called party,
      # D() for post-dial DTMF, L() for call duration limits
      #astflags = args.shift if args.count
      options[:callerID] = @chanvars['CALLERID(num)'] if @chanvars.has_key?('CALLERID(num)')
      options[:headers]  = set_headers(@chanvars)

      show "Destination: #{destinations.inspect}, Options: #{options.inspect}"
      result = @current_call.transfer destinations, options

      # Map the Tropo result to the Asterisk DIALSTATUS channel variable
      @chanvars['DIALSTATUS'] = case result.name.downcase
      when 'transfer'    then 'ANSWER'
      when 'success'     then 'ANSWER'
      when 'timeout'     then 'NOANSWER'
      when 'error'       then 'CONGESTION'
      when 'callFailure' then 'CHANUNAVAIL'
      else 'CONGESTION'
      end
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Implements Answering Machine Detection
    # AGI: http://www.voip-info.org/wiki/index.php?page=Asterisk+cmd+AMD
    # Tropo: http://blog.tropo.com/2010/12/17/human-vs-answering-machine-detection/
    #
    # @param [Hash] the options used to place the dial
    #
    # @return [String] the response in AGI raw form
    def amd(options={})
      check_state

      # TODO: It is not currently possible to do the in-depth analysis on Tropo
      # (word-count, number of words, silence threshold) that Asterisk supports
      # with app_amd.  Thus we have to ignore any passed-in args.
      starttime = Time.now
      @current_call.record ".", {
          :beep => false,
          :timeout => 10,
          :silenceTimeout => 1,
          :maxTime => 10
          }

      endtime = Time.now
      difference = (endtime - starttime).to_i

      if difference < 3
          @chanvars['AMDSTATUS'] = 'HUMAN'
          # Since :silenceTimeout is 1 above, fudge the silenceDuration
          # and afterGreetingSilence values
          @chanvars['AMDCAUSE'] = "HUMAN-1-1"
      else
          @chanvars['AMDSTATUS'] = 'MACHINE'
          @chanvars['AMDCAUSE']  = "TOOLONG-#{difference.to_s}"
      end
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Play the given file
    # AGI: http://www.voip-info.org/wiki/view/stream+file
    #
    # The enhanced capability won't work for now, since Adhearsion expects back ASCII single digits
    # enhanced_input_example {
    #   postal_code = input 1, :play => { :prompt => 'Please enter your post code?',
    #                                     :timeout => 5,
    #                                     :choices => '[5 DIGITS]',
    #                                     :terminator => '#' }.to_json
    #
    #   ahn_log.postal_code.debug postal_code
    #   play "You entered"
    #   say_digits postal_code
    # }
    #
    # @param [Hash] the options used to play the file back
    #
    # @return [String] the response in AGI raw form
    def file(options={})
      check_state

      @wait_for_digits_options = parse_input_string options[:args][0], 16
      if @wait_for_digits_options.nil?
        prompt, escape_digits = extract_prompt_and_escape_digits(options[:args][0])

        asterisk_sound_url = fetch_asterisk_sound(prompt)
        prompt = asterisk_sound_url if asterisk_sound_url

        if escape_digits.nil?
          @current_call.say prompt, :voice => @tropo_voice
          result = @agi_response + "0 endpos=0\n"
        else
          # Timeout is set to 0 so we return immediately after playback
          response = @current_call.ask prompt, { :choices    => create_choices(escape_digits),
                                                 :choiceMode => 'keypad',
                                                 :timeout    => 0 }
          digit = response.value.nil? ? 0 : response.value[0]
          result = @agi_response + digit.to_s + " endpos=0\n"
        end
      end
      result
    rescue => e
      log_error(this_method, e)
    end
    alias :streamfile :file

    ##
    # Grabs all of the SIP headers off of the current session/call
    # This is a work around until the $currentCall.getHeaderMap works, currently a bug in the Ruby shim
    #
    # @return [Hash] all of the SIP headers on the current session
    def getheaders
      hash = {}
      # We are accessing the Java object directly, so we get a Java HashMap back
      hash = hashmap_to_hash($incomingCall.getHeaderMap) if $incomingCall != 'nullCall'
      hash.merge!({ :tropo_tag => $tropo_tag }) if $tropo_tag
      hash
    end

    ##
    # Initiates a hangup to the Tropo call object
    # AGI: http://www.voip-info.org/wiki/view/hangup
    # Tropo: https://www.tropo.com/docs/scripting/hangup.htm
    #
    # @return [String] the response in AGI raw form
    def hangup
      @current_call.hangup
      @agi_response + "1\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Initiates a conference
    # AGI: http://www.voip-info.org/wiki/view/Asterisk+cmd+MeetMe
    # Tropo: https://www.tropo.com/docs/scripting/conference.htm
    #
    # param [Hash] a hash of items
    # @return [String] the response in AGI raw form
    def meetme(options={})
      check_state

      options = options[:args][0].split('|')
      @current_call.conference options[0].chop
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end
    alias :conference :meetme

    ##
    # Traps any unknown/unsupported commands and logs an error mesage to the Tropo debugger
    #
    # @param [Object] the arguments used to make the method call
    #
    # @return [String] the response in AGI raw form
    def method_missing(method, *args)
      show "Invalid or unknown command: #{method.inspect}"
      return "510 result=Invalid or unknown Command\n"
    end

    ##
    # Initiates a recording of the call
    # AGI:
    #  - http://www.voip-info.org/index.php?content_id=3134
    #  - http://www.voip-info.org/wiki/view/Asterisk+cmd+MixMonitor
    # Tropo: https://www.tropo.com/docs/scripting/startcallrecording.htm
    #
    # @param [Hash] options used to build the startCallRecording
    #
    # @return [String] the response in AGI raw form
    def monitor(options={})
      check_state

      @current_call.startCallRecording options[:args]['uri'], options[:args]
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end
    alias :mixmonitor :monitor
    alias :startcallrecording :monitor

    ##
    # Initiates a playback to the Tropo call object for Speech Synthesis/TTS
    # AGI: http://www.voip-info.org/index.php?content_id=3168
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] the options used for the Tropo say method
    #
    # @return [String] the response in AGI raw form
    def playback(options={})
      check_state

      asterisk_sound_url = fetch_asterisk_sound(options[:args][0])
      if asterisk_sound_url
        text = asterisk_sound_url
      else
        text = options[:args][0]
      end
      @current_call.say text, :voice => @tropo_voice
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end
    alias :saynumber :playback
    alias :say :playback

    ##
    # Reads a #-terminated string of digits a certain number of times from the user in to the given variable.
    # AGI: https://wiki.asterisk.org/wiki/display/AST/Application_Read
    # Tropo: https://www.tropo.com/docs/scripting/ask.htm
    #
    # @param [Hash] the options used for the Tropo ask method
    #
    # @return [String] the response in the AGI raw form
    def read(options={})
      check_state

      # Check to see if the READ arguments were sent in quotes, like from Asterisk-Java
      options[:args] = options[:args][0].split(',', -4) if options[:args].length == 1

      # Set defaults
      prompt, choices, attempts, timeout = 'silence', '[1-255 DIGITS]', 1, 30

      # Set the prompt
      prompt = options[:args][1]  if options[:args][1] != ""
      asterisk_sound_url = fetch_asterisk_sound(prompt)
      prompt = asterisk_sound_url if asterisk_sound_url

      # Set other values if provided
      choices = "[1-#{options[:args][2]} DIGITS]" unless options[:args][2].nil? || options[:args][2].empty?
      attempts = options[:args][4] unless options[:args][4].nil? || options[:args][4].empty?
      timeout = options[:args][5].to_f unless options[:args][5].nil? || options[:args][5].empty?

      response = nil
      attempts.to_i.times do
        response = @current_call.ask prompt, { :choices    => choices,
                                               :choiceMode => 'keypad',
                                               :terminator => '#',
                                               :timeout    => timeout }
        break if response.value
      end

      # Set the variable the user has specified for the value to insert into
      @chanvars[options[:args][0]] = response.value
      @agi_response + "0\n"
    end

    ##
    # Used to change the voice being used for speech recognition/ASR
    #
    # @param [Hash] options used set the recognizer
    #
    # @return [String] the response in AGI raw form
    def recognizer(options={})
      if options[:args][0] == 'default'
        @tropo_recognizer = @tropo_agi_config['tropo']['recognizer']
      else
        @tropo_recognizer = options[:args][0]
      end
      @agi_response + "0\n"
    end

    ##
    # Records a user input
    # AGI: http://www.voip-info.org/index.php?content_id=3176
    # Tropo: https://www.tropo.com/docs/scripting/record.htm
    #
    # @param [Hash] the options used for the record
    #
    # @return [String] the response in AGI raw form
    def record(options={})
      check_state

      options = options[:args][0].split
      silence_timeout = strip_quotes(options[options.length - 1]).split('=')
      beep = true if strip_quotes(options[5]) == 'BEEP'
      options = { :recordURI      => strip_quotes(options[0]),
                  :silenceTimeout => silence_timeout[1].to_i / 1000,
                  :maxTime        => strip_quotes(options[3]).to_i,
                  :recordFormat   => strip_quotes(options[1]),
                  :terminator     => strip_quotes(options[2]),
                  :beep           => beep }
      ssml =
      @current_call.record '<speak> </speak>', options
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Provides the ability to redirect a call after it is answered
    # Tropo: https://www.tropo.com/docs/scripting/redirect.htm
    #
    # @return [String] the response in AGI raw form
    def redirect(options={})
      check_state

      @current_call.redirect options[:args][0]
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Provides the ability to reject a call before it is answered
    # Tropo: https://www.tropo.com/docs/scripting/reject.htm
    #
    # @return [String] the response in AGI raw form
    def reject
      @current_call.reject
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Provides a RAW say capability
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] options used to build the say
    #
    # @return [String] the response in AGI raw form
    def say(options={})
      check_state

      @current_call.say options[:args]['prompt'], options[:args]
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Plays back digits using SSML
    # AGI: http://www.voip-info.org/index.php?content_id=3182
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] options used to build the say
    # @return [String] the response in AGI raw form
    def saydigits(options={})
      check_state

      ssml = "<speak><say-as interpret-as='vxml:digits'>#{options[:args][0]}</say-as></speak>"
      @current_call.say ssml, :voice => @tropo_voice
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Speaks back individual characters in a string
    # AGI: http://www.voip-info.org/wiki/index.php?page=Asterisk+cmd+SayPhonetic
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] options used to build the say
    #
    # @return [String] the response in AGI raw form
    def sayphonetic(options={})
      check_state

      text = ''
      options[:args][0].split(//).each do |char|
        text = text + char + ' '
      end
      @current_call.say text, :voice => TROPO_VOICE
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # ====> TO BE IMPLEMENTED <====
    #
    # Speaks back the time
    # AGI:
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] options used to build the say
    #
    # @return [String] the response in AGI raw form
    def saytime(options={})
      check_state

      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Plays DTMF/touch tone digits to the audio channel
    # AGI: http://www.voip-info.org/index.php?content_id=3184
    # Tropo: https://www.tropo.com/docs/scripting/say.htm
    #
    # @param [Hash] options used to build the say
    #
    # @return [String] the response in AGI raw form
    def senddtmf(options={})
      check_state

      base_uri = 'http://hosting.tropo.com/49767/www/audio/dtmf/'
      options[:args][0].split(//).each do |char|
        case char
        when '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'a', 'b', 'c', 'd'
          playback({ :args => [ base_uri + "#{char}.wav" ] })
        when '#'
          playback({ :args => [ base_uri + "#.wav" ] })
        else
          show "Cannot play DTMF with: #{char.inspect}"
        end
      end
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Returns the current state of the call
    # AGI: http://www.voip-info.org/wiki/view/channel+status
    #
    # @return [String] the AGI response
    def status(options={})
      case @current_call.state
      when 'RINGING'
        status = 4
      when 'ANSWERED'
        status = 6
      else
        status = 0
      end
      @agi_response + status.to_s + "\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Returns the current state of the call
    # AGI: http://www.voip-info.org/wiki/view/channel+status
    #
    # @return [String] the AGI response
    def stopcallrecording(options={})
      check_state

      @current_call.stopCallRecording
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end
    alias :monitor_stop :stopcallrecording
    alias :mixmonitor_stop :stopcallrecording

    ##
    # Handles the storing/retrieving of User Variables associated to the call
    # AGI:
    #  - http://www.voip-info.org/wiki/view/set+variable
    #  - http://www.voip-info.org/wiki/view/get+variable
    #
    # @param [Hash] options used to build the say
    #
    # @return [String] the response in AGI raw form
    def channel_variable(options={})
      case options[:action]
      when 'set'
        key_value = options[:args][0].split(' ', 2)
        @chanvars[strip_quotes(key_value[0])] = strip_quotes(key_value[1])
        @agi_response + "0\n"
      when 'get'
        varname = strip_quotes(options[:args][0].to_s)
        if @chanvars[varname]
          @agi_response + '1 (' + @chanvars[varname].to_s + ")\n"
        else
          # Variable has not been set
          @agi_response + "0\n"
        end
      end
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Used to change the voice being used for speech synthesis/TTS
    #
    # @param [Hash] options used set the voice
    #
    # @return [String] the response in AGI raw form
    def voice(options={})
      if options[:args][0] == 'default'
        @tropo_voice = @tropo_agi_config['tropo']['voice']
      else
        @tropo_voice = options[:args][0]
      end
      @agi_response + "0\n"
    end

    ##
    # Provides the ability to wait a specified period of time
    # Tropo: https://www.tropo.com/docs/scripting/wait.htm
    #
    # @return [String] the response in AGI raw form
    def wait(options={})
      @current_call.wait options[:args][0].to_i * 1000
      @agi_response + "0\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Asks the user to input digits, may work with touch tones or speech recognition/ASR
    # AGI: http://www.voip-info.org/wiki/view/wait+for+digit
    # Tropo: https://www.tropo.com/docs/scripting/ask.htm
    #
    # @param [Hash] options used to build the ask
    #
    # @return [String] the response in AGI raw form
    def wait_for_digits(options={})
      check_state

      if @wait_for_digits_options.nil?
        timeout = strip_quotes(options[:args][0].split(' ')[1]).to_i
        timeout = 1000 if timeout == -1
        timeout = timeout / 1000
        response = @current_call.ask('', { :timeout    => timeout,
                                           :choices    => '[1 DIGIT], *, #',
                                           :choiceMode => 'keypad' })
      else
        response = @current_call.ask(@wait_for_digits_options['prompt'], @wait_for_digits_options)
      end
      digit = response.value.nil? ? 0 : response.value[0]
      @agi_response + digit.to_s + "\n"
    rescue => e
      log_error(this_method, e)
    end

    ##
    # Builds a hash of the available Asterisk Sound files from a JSON file stored on Tropo
    #
    # @return [Hash] all of the sound files available to be played back
    def asterisk_sound_files
      JSON.parse(Net::HTTP.get(URI.parse(@tropo_agi_config['asterisk']['sounds']['available_files'])))
    end

    private

    ##
    # Automatically answers the call/session if not explicitly done
    def check_state
      case @current_call.state
      when 'DISCONNECTED'
        raise RuntimeError, '511 result=Command Not Permitted on a dead channel'
      when 'RINGING'
        @current_call.answer
        # Sleep to allow audio to settle, in the case of Skype
        sleep 2
      end
      true
    end

    ##
    # Converts the choices passed in a STREAM FILE into the requisite comma-delimited format for Tropo
    #
    # @param [required, String] escape_digits to convert
    def create_choices(escape_digits)
      choices = ''
      # 1.3.1 does not have the each_char method on the String class
      if JRUBY_VERSION == '1.3.1'
        escape_digits.each_byte { |char| choices = choices + char.chr + ','  }
      else
        escape_digits.each_char { |char| choices = choices + char + ','  }
      end
      choices.chop
    end

    ##
    # Extracts the prompt and escape digits from a STREAM FILE request
    #
    # @param [required, String] original_string to extract the prompt and escape digits out of
    def extract_prompt_and_escape_digits(original_string)
      original_string.gsub!('"', '')
      match_data = original_string.match /\d{1,}\#$|\d{1,}$|\d{1,}\*\#$|\d{1,}\#\*$|\d{1,}\*|\#|\*$/
      if match_data.nil?
        return original_string, nil
      else
        return match_data.pre_match.rstrip, match_data[0]
      end
    end

    ##
    # Returns the URI location of the Asterisk sound file if it is available
    #
    # @param [String] the name of the sound file to be played
    #
    # @return [String] the URL to play the file from if the filename exists
    def fetch_asterisk_sound(text)
      text = strip_quotes text
      if @tropo_agi_config['asterisk']['sounds']['enabled']
        if @asterisk_sound_files[text]
          return @tropo_agi_config['asterisk']['sounds']['base_uri'] + '/' +
                 @tropo_agi_config['asterisk']['sounds']['language'] + '/' +
                 @asterisk_sound_files[text]
        end
      end
      false
    end

    ##
    # This is a work around until the $currentCall.getHeaderMap works, currently a bug in the Ruby shim
    #
    # @param [JavaHashMap] the Java HashMap to convert to a Ruby Hash
    #
    # @return [Hash] the converted native Ruby hash
    def hashmap_to_hash(hashmap)
      # We get the Java iterator off of the object
      iter = hashmap.keySet.iterator
      hash = {}

      # We then iterate through the HashMap and build a native Ruby hash
      while iter.hasNext
        key = iter.next
        hash[key] = hashmap.get(key)
      end
      hash
    end

    ##
    # Logs formatted errors to the Tropo debugger
    #
    # @param [String] the aciton that was requested
    # @param [String] the error itself
    #
    # @return [String] the response in AGI raw form
    def log_error(action, error)
      @current_call.log '====> Tropo AGI ACTION ERROR - Start <===='
      show "Error: Unable to execute the #{action} request. call_active? #{@current_call.isActive.inspect}"
      show "Error output: #{error.inspect}"
      show "******************************** TRACE ********************************"
      error.backtrace.each do |line|
        show line
      end
      show "******************************** END TRACE ********************************"
      @current_call.log '====> Tropo AGI ACTION ERROR - End <===='

      # Return an error based on the error encountered
      case error.to_s
      when '511 result=Command Not Permitted on a dead channel'
        error.to_s + "\n"
      else
        @agi_response + "-1\n"
      end
    end

    ##
    # Parses the destinations sent over the AGI protocol into an array of dialable destinations
    # Also converts the Asterisk style of SIP/ to sip:, the proper SIP URI format
    #
    # @param [Array] the unformatted destinations to be parsed from AGI
    #
    # @return [Array] an array of destinations
    def parse_destinations(destinations)
      destinations_array = []
      destinations.each do |destination|
        destination = destination.reverse.chop.reverse if destination[0] == 34
        if destination.match /^(sip|SIP|tel)(\:|\/)\w{1,}$/
          destinations_array << destination.gsub('SIP/', 'sip:')
        else
          destinations_array << destination.gsub('SIP/', 'sip:')
        end
      end
      destinations_array
    rescue => e
      show "parse_destinations method error: #{e.inspect}"
    end

    ##
    # Parses the STREAM FILE for input to see if it is a JSON string and if so return the Hash
    #
    # @param [String] the string to parse
    #
    # @return [Hash, nil] the hash if it was JSON, nil if it was not
    def parse_input_string(string, leftchop)
      JSON.parse string[0..-leftchop].gsub("\\", '')
    rescue => e
      nil
    end

    ##
    # Preps @chanvars to be set as headers
    #
    # @return [Hash] the formatted headers
    def set_headers(vars)
      show "Headers to map: #{vars.inspect}"
      headers = {}
      vars.each do |k, v|
        headers['x-tropo-' + k.to_s] = v.to_json
      end
      headers
    end
  end#end class Commands

  ##
  # Creates a new instance of TropoAGItate
  #
  # @param [Object] the currentCall object of Tropo
  # @param [String] the AGI URI of the AGI server
  # @param [Hash] the configuration details of using/not using the built-in Asterisk Sound files
  # @return [Object] instance of TropoAGItate
  def initialize(current_call, current_app)
    @current_call     = current_call
    @current_app      = current_app

    @tropo_agi_config = tropo_agi_config
    show "With Configuration  #{@tropo_agi_config.inspect}"
    @commands = Commands.new(@current_call, @tropo_agi_config)

    @agi_uri = URI.parse @tropo_agi_config['agi']['uri']
    @agi_uri.port = 4573 if @agi_uri.port.nil?
    @agi_exten = 's'
  rescue => e
      show "Could not find your configuration file. #{e.inspect}"
      # Could not find any config, so failing over to the default location
      failover('sip:9991443146@sip.tropo.com')
      show 'Session sent to default backup location, Now aborting the script'
      abort
  end

  ##
  # Executes the loop that sends and receives the AGI messages to and from the AGI server
  #
  # @return [Boolean] whether the socket is open or not
  def run
    if create_socket_connection
      until @agi_client.closed?
        begin
          command = @agi_client.gets
          show "Raw string: #{command}"
          result = execute_command command
          @agi_client.write result
        rescue => e
          @current_call.log '====> Broken pipe to the AGI server, Adhearsion tends to drop the socket after sending a hangup. <===='
          show "Error is: #{e}"
          @current_call.hangup
        end
      end
      close_socket
    end
  end
  alias :start :run

  ##
  # Creates the TCP socket connection
  #
  # @return nil
  def create_socket_connection
    @current_call.log "Connecting to AGI server at #{@agi_uri.host}:#{@agi_uri.port}"
    @agi_client = TCPSocket.new @agi_uri.host, @agi_uri.port
    @agi_client.write initial_message(@agi_uri.host, @agi_uri.port, @agi_uri.path[1..-1])
    true
  rescue => e
    # If we can not open the socket to the AGI server, play/log an error message and hangup the call
    error_message = 'We are unable to connect to the A G I server at this time, please try again later.'
    @current_call.log "====> #{error_message} <===="
    @current_call.log e
    failover @tropo_agi_config['tropo']['next_sip_uri']
    false
  end

  ##
  # Closes the socket
  #
  # @return [Boolean] indicates if the socket is open or closed, true if closed, false if open
  def close_socket
    @agi_client.close rescue
    @agi_client.closed?
  end

  ##
  # Sends the initial AGI message to the AGI server
  # AGI: http://www.voip-info.org/wiki/view/Asterisk+AGI
  #
  # @param [String] the hostname of the AGI server
  # @param [Integer] the port of the AGI server
  # @param [String] the context to be used
  #
  # @return [String] the response in AGI raw form
  def initial_message(agi_host, agi_port, agi_context)
    # Grab the headers and then push them in the initial message
    headers = @commands.getheaders
    rdnis = 'unknown'
    rdnis = headers['x-sbc-diversion'] if headers['x-sbc-diversion']

<<-MSG
agi_network: yes
agi_network_script: #{agi_context}
agi_request: agi://#{agi_host}:#{agi_port}/#{agi_context}
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
agi_dnid: #{@current_call.calledID}
agi_rdnis: #{rdnis}
agi_context: #{agi_context}
agi_extension: #{@agi_exten}
agi_priority: 1
agi_enhanced: 0.0
agi_accountcode: 0
agi_threadid: #{Thread.current.to_s}
tropo_headers: #{headers.to_json if headers.keys.length > 0}

MSG
  end

  ##
  # Executes the given command from AGI to Tropo
  #
  # @param [String] the raw AGI form from the AGI server
  #
  # @return [String] the response to the command in raw AGI form
  def execute_command(data)
    data = "HANGUP" if data.nil?
    options = parse_command(data)
    case options[:action]
    when 'answer', 'hangup'
      @commands.send(options[:action].to_sym)
    when 'set', 'get'
      if options[:command].downcase == 'variable'
        @commands.channel_variable(options)
      elsif options[:command].downcase == 'callerid' || options[:command].downcase == 'calleridname'
        @commands.callerid(options)
      end
    when 'exec', 'stream', 'channel'
      @commands.send(options[:command].downcase.to_sym, options)
    when 'wait'
      @commands.wait_for_digits(options)
    when 'record'
      @commands.record(options)
    else
      show "Invalid or unknown command #{data}"
      return "510 result=Invalid or unknown Command\n"
    end
  end

  ##
  # Takes the AGI response from the AGI server, breaks into the arguments
  # and returns the commands to be executed stripped of quotes
  #
  # @param [String] the AGI server response
  #
  # @return [Hash] the command
  def parse_command(data)
    # Break down the command into its component parts
    parts = data.match /^(\w+)\s*(\w+|"\w+")?\s*(.*)?$/
    return if parts.nil?
    part1, part2, part3 = parts[1], parts[2], parts[3]
    command = { :action => part1.downcase }
    command.merge!({ :command => strip_quotes(part2.downcase) }) unless  part2.nil?
    command.merge!({ :args => parse_args(part3) }) unless part3.nil? || part3.empty?
    show "command #{command.inspect}"
    command
  end

  ##
  # Parses the arguments to strip quotes, put into an array or a hash if JSON
  #
  # @param [String] the arguments to be parsed
  #
  # @return [Array, Hash] the parsed arguments
  def parse_args(parts)
    begin
      args = JSON.parse strip_quotes(parts.clone)
    rescue
      # Split with a RegEx, since we may have commas inside of elements as well as
      # delimitting them
      elements = parts.split(/(,|\r\n|\n|\r)(?=(?:[^\"]*\"[^\"]*\")*(?![^\"]*\"))/m)
      # Get rid of the extraneous commas
      elements.delete(",")
      args = []
      elements.each do |ele|
        args << strip_quotes(ele)
      end
    end
    args
  end

  ##
  # This method fails over to the backup SIP URI or plays the error message if no backup
  # provided
  #
  # @return nil
  def failover(location)
    if @current_call.isActive
      @current_call.answer
      if location
        begin
          @current_call.transfer location
        rescue => e
          show "Unable to transfer to your next_sip_uri location #{e}"
        end
      else
        error_message = 'We are unable to connect to the fail over sip U R I.  Please try your call again later.'
        @current_call.log "====> #{error_message} <===="
        @current_call.say error_message, :voice => @tropo_voice
        @current_call.hangup
      end
    end
  end

  ##
  # Load the configuration from the current account FTP/WebDAV files of Tropo
  #
  # @return [Hash] the configuration details
  def tropo_agi_config
    # Find the account number this app is running under
    account_data = fetch_account_data

    # Try from the www directory on the Tropo file system
    result = fetch_config_file "/#{account_data[1]}/www/tropo_agi_config/tropo_agi_config.yml"
    return YAML.load(result.body) if result.code == '200'
    show "Can not find config file. #{result.body}"

    # No config file found
    raise RuntimeError, "Configuration file not found"
  end

  ##
  # Fetches the account data
  #
  # @return [Array] the account data details derived from the underlying directory structure
  def fetch_account_data
    @current_app.baseDir.to_s.match /(\d+)$/
  end

  ##
  # Fetches the configuration file
  #
  # @param [String] the resource where the file is to be found
  #
  # @return [Object] the resulting HTTP object
  def fetch_config_file(resource)
    url = URI.parse("http://hosting.tropo.com")
    Net::HTTP.start(url.host, url.port) {|http|
      http.get resource
    }
  end

  ##
  # A special class to mimic some of Asterisk's behavior toward certain
  # channel variables.
  class MagicChannelVariables
    include Enumerable

    def initialize(inputs = {})
      @variables = {:callerid => {}}
      inputs.each_pair do |k,v|
        set(k,v)
      end
    end

    def set(k, v)
      case k
      when "CALLERIDNAME", "CALLERID(name)"
        @variables[:callerid][:name] = v
      when "CALLERIDNUM", "CALLERID(num)"
        @variables[:callerid][:num] = v
      when "CALLERID", "CALLERID(all)"
        # Parse out the callerID details
        # MUST be in the form of "Name"<number>
        # See http://www.voip-info.org/wiki/view/set+callerid
        name, number = v.scan(/(?:"([^"]*)"\s*){0,1}<([^>]*)>/).first
        @variables[:callerid][:name] = name   if !name.nil?
        @variables[:callerid][:num]  = number if !number.nil?
      else
        @variables[k] = v
      end
    end
    alias :[]= :set

    def get(k)
      log "Fetching value for #{k} with #{@variables.inspect}"
      case k
      when "CALLERIDNAME", "CALLERID(name)"
        @variables[:callerid][:name]
      when "CALLERIDNUM", "CALLERID(num)"
        @variables[:callerid][:num]
      when "CALLERID", "CALLERID(all)"
        "\"#{@variables[:callerid][:name]}\" <#{@variables[:callerid][:num]}>"
      else
        @variables[k] || nil
      end
    end
    alias :[] :get

    def has_key?(k)
      case k
      when "CALLERIDNAME", "CALLERID(name)"
        !@variables[:callerid][:name].nil?
      when "CALLERIDNUM", "CALLERID(num)"
        !@variables[:callerid][:num].nil?
      when "CALLERID", "CALLERID(all)"
        # Return true if either component variable is set.
        !(@variables[:callerid][:name].nil? && @variables[:callerid][:num].nil?)
      else
        @variables.has_key?(k)
      end
    end

    def each
      @variables.each do |k,v|
        # Convert key names that would result in invalid JSON
        k = k.to_s.gsub(/[\(\)]/, '')
        yield k,v
      end
    end
    alias :each_pair :each

    def method_missing(m, *args)
      @variables.send(m, *args)
    end
  end

  ##
  # This class emulates the Tropo callObject object for the purposes of allowing
  # Tropo-AGItate to emulate Asterisk "h" (hangup) and "failed" special calls.
  class DeadCall
    attr_accessor :callerID, :calledID, :callerName, :id

    def initialize(system, destination, info)
      require 'digest/md5'
      require 'time'
      # Proxy object to the global namespace
      @system = system
      # Fake a channel ID since we don't have a real channel to provide one
      @id         = Digest::MD5.hexdigest(self.hash.to_s + Time.now.usec.to_s)
      @callerID   = info[:callerID]
      @calledID   = destination
      @callerName = info[:callerName] || ""
      @active     = true
    end

    def isActive
      # This is probably a lie, but without it the read loop bails.
      # A dead channel is accessible for getting variables, but not much else.
      @active
    end

    def log(message)
      @system.send :log, message
    end

    def hangup
      @active = false
    end

#    def method_missing(method, *args)
#      @system.send(method.to_sym, *args)
#    end
  end
end#end class TropoAGItate

def agitate_factory
  log "====> Starting Tropo-AGItate <===="

  # If this is an outbound request place the call
  # see: https://www.tropo.com/docs/scripting/call.htm
  if $destination
    options = {}
    # User may pass in the caller ID to use
    options[:callerID] = $caller_id if $caller_id
    # User may pass in text or voice to use for the channel
    options[:channel]  = $channel || 'voice'
    #  User may pass in AIM, GTALK, MSN, JABBER, TWITTER, SMS or YAHOO, SMS is default
    options[:network]  = $network || 'SMS'
    # Time tropo will wait before hanging up, default is 30
    options[:timeout]  = $timeout.to_i if $timeout

    # If voice turn the phone number into a Tel URI, but only if not a SIP URI
    $destination = 'tel:+' + $destination if options[:channel].downcase == 'voice' && $destination[0..2] != 'sip'

    log "====> Calling to: #{$destination} - with these options: #{options.inspect} <===="
    # Place the call

    result = call $destination, options
  end

  if $currentCall
    # This is a connected call
    agitate = TropoAGItate.new $currentCall, $currentApp
  else
    # If the call failed, let the application know.
    deadcall = TropoAGItate::DeadCall.new(self, $destination, options)
    agitate = TropoAGItate.new deadcall, $currentApp
    agitate.agi_exten = 'failed'
    log "Result: #{result.inspect}"
    agitate.commands.chanvars['REASON'] = case result.name
    when 'timeout'     then 0
    when 'hangup'      then 1
    when 'error'       then 8
    when 'callfailure' then 8
    end
  end
  agitate.agi_uri.path = $agi_path if $agi_path
  agitate
end

agitate_factory.run if !@tropo_testing
