# The main AGI entry point
tropo_agi {
  answer
  +hello_world
  hangup
}


# Invokes the native Tropo ask for Speech Recognition / ASR
# Related Tropo method: https://www.tropo.com/docs/scripting/ask.htm
ask_example {
  result = execute 'ask', { :prompt  => 'Please enter your zip code', 
                            :choices => 'zipcode([5 DIGITS])' }.to_json
  # Get rid of the '200 result =' and then parse the JSON
  response = JSON.parse(result[11..-1])
  ahn_log.debug response
}

# We have lots of Asterisk sounds!
asterisk_sounds_example {
  play 'tt-monkeys'
}

# You may dial other SIP addresses, or telephone numbers as you like
# Formats may be:
#  SIP/
#  sip:
#  tel:+
# Related Tropo method: https://www.tropo.com/docs/scripting/transfer.htm
dial_example {
  dial 'sip:9991443146@sip.tropo.com'
}

hello_world {
  play 'tt-monkeys'
}

# Works as input should, only accepting DTMF
# Related Tropo method: https://www.tropo.com/docs/scripting/ask.htm
input_example {
  postal_code = input 5, :play         => 'Please enter your post code?',
                         :timeout      => 2
                         
  ahn_log.postal_code.debug postal_code
  play "You entered"
  say_digits postal_code
}

# Find out if this is a Tropo session or an Asterisk one
is_tropo? {
  if type == 'TROPO'
    play "Yippeee! It is a Tropo call!"
  else
    play "No, this is a good old Asterisk call"
  end
}

# Related Tropo method: https://www.tropo.com/docs/scripting/say.htm
say_digits_example {
  say_digits '12345'
}

# Uses the native Tropo say method for Speech-Synthesis/TTS, will not play Asterisk sound files like play will
# Related Tropo method: https://www.tropo.com/docs/scripting/say.htm
say_example {
  execute 'say', { :prompt => 'I like to have weasels in my cloud.', :voice => 'simon' }.to_json
}

# If this is a Tropo call, then all of the SIP headers for the session are available
show_call_data {
  ahn_log.tropo_headers_str.debug tropo_headers
  tropo_headers = JSON.parse self.tropo_headers
  ahn_log.tropo_headers_hash.debug tropo_headers
  play "The content type is " + tropo_headers['Content-Type']
  +asterisk_sounds_example
}

# Monitor and Mixmonitor behave the same, may also be invoked as startCallRecording
# Related Tropo method: https://www.tropo.com/docs/scripting/startcallrecording.htm
monitor_example {
  play 'About to start call recording'
  execute 'monitor', { :uri                 => 'http://tropo-audiofiles-to-s3.heroku.com/post_audio_to_s3?filename=voicemail.mp3',
                       :format              => 'mp3',
                       :method              => 'POST',
                       :transcriptionOutURI => 'mailto:jsgoecke@voxeo.com' }.to_json
  play 'Call recording started!'
  play 'Thats it folks!'
  execute 'monitor_stop', ''
  play 'Recording stopped!'
}

# Related Tropo method: https://www.tropo.com/docs/scripting/record.htm
record_prompt_example {
  play 'Please record after the beep'
  record 'http://tropo-audiofiles-to-s3.heroku.com/post_audio_to_s3?filename=voicemail.mp3',
         :silence => 5, 
         :maxduration => 120
}

# Allows you to set and retrieve variables on the session
# These also get passed as custom SIP headers, prepended with 'x-tropo' when you dial/transfer a call
variables_example {
  set_variable('foobar', 'green')
  ahn_log.debug get_variable('foobar')
}

# We have lots of Asterisk sounds!
asterisk_sounds_example {
  play 'tt-monkeys'
}

# Allows you to send standard DTMF digits
send_dtmf_example {
  dtmf '1234567890#*'
}

# Start menu example
# Related Tropo method: https://www.tropo.com/docs/scripting/ask.htm
menu_example {
  menu 'welcome', 'for spanish press 4',
       :timeout => 8.seconds, :tries => 3 do |link|
    link.shipment_status  1
    link.ordering         2
    link.representative   3
    link.spanish          4
    link.employee         500..599

    link.on_invalid { play 'invalid' }

    link.on_premature_timeout do |str|
      play 'sorry'
    end

    link.on_failure do
      play 'goodbye'
      hangup
    end
  end
}

shipment_status {
  play 'I surely do not know your shipment status.'
}

ordering {
  play 'Go somewhere else and order.'
}

representative {
  play 'No representatives here.'
}

spanish {
  play 'e 2 brutus?'
}

employee {
  play "The person at"
  say_digits extension
  play "went home for the day."
}
# End menu example
