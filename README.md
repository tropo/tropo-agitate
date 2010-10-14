Tropo AGItate
==============

Tropo AGItate lets you run Asterisk AGI applications on the Tropo cloud communications platform.

Description
-----------

Provides a script to emulate the Fast Asterisk Gateway Interface [FastAGI]([http://www.voip-info.org/wiki/view/Asterisk+FastAGI "FastAGI") protocol on [Tropo](http://tropo.com "Tropo"). While most of the development and testing has been done using [Adhearsion](http://adhearsion.com "Adhearsion"), we stayed with the proper Asterisk AGI implementation. Therefore this script should work with any FastAGI server including [PHPAGI](http://phpagi.sourceforge.net/ "PHPAGI") and [Asterisk-Java](http://asterisk-java.org/ "Asterisk Java"). We will be doing more testing with alternative frameworks soon and reporting back.

Installation
-----------

This project allows you to control the Tropo AGI via an Adhearsion dialplan context. 

* Create a free account at [Tropo](http://tropo.com "Tropo").

* Install [Adhearsion 0.8.6+](http://adhearsion.com "Adhearsion"). You can install this on your local computer.

<pre>
  gem install adhearsion
</pre>

* Create a simple dialplan, or use some of the examples provided

<pre>
  tropo_agi {
    play "Wow. My first app! Tropo really is this easy!"
  }
</pre>

* Ensure your Adhearsion app is running and has a public IP. You may need to port forward 4573 on your firewall.

* Create your Tropo application

Instructions may be found [here](https://www.tropo.com/docs/scripting/quickstart.htm "Quick Start").

* Set your Tropo app to use the [lib/tropo-agitate.rb](https://github.com/tropo/tropo-agitate/raw/master/lib/tropo-agitate.rb) script

  * Load the file directly to the Github file location [lib/tropo-agitate.rb](https://github.com/tropo/tropo-agitate/raw/master/lib/tropo-agitate.rb)
  * Host the 'tropo-agitate.rb' yourself and provide a public URL for access 
  * Add it to your Tropo FTP/WebDAV account

* Modify the configuration file and post it to your Tropo FTP/WebDAV account

  * First set your configuration settings in the [tropo_agi_config/tropo_agi_config.yml](https://github.com/tropo/tropo-agitate/raw/master/tropo_agi_config/tropo_agi_config.yml "tropo_agi_config.yml") file
  * Then upload to your [Tropo FTP/WebDAV](https://www.tropo.com/docs/scripting/tropohosting.htm) account placing in root/www/tropo_agi_config

* Use a SIP client (like Blink for Mac) and dial the SIP Voice account listed under your application, may use Skype too!

* Happy Tropo-ing!

Placing Outbound Calls
----------------------

Tropo supports placing outbound calls with the [Session API](https://www.tropo.com/docs/scripting/sessions.htm). AGItate allows for receiving a predefined set of parameters to place the call and tag it so you may associate it to your request once it reaches your AGI server. The parameters supported are:

* destination

	The destination to make a call to or send a message to. This may currently take one of the following forms:

	14155551212 - The telephone number to dial with the country code. 
	sip:username@doamin.com - The SIP URI to dial
	username - The IM or Twitter user name.

	Some IM networks like Google Talk and Live Messenger include a domain as part of the user name. For those networks, include the domain: username@gmail.com

	When making a voice call, you can specify dialing options as part of the number:

	You can also list multiple phone numbers or SIP addresses (or both!) as a comma separated list

* caller_id

	The Caller ID for the session's origin. For example, if the number (407)555-1212 called (407)555-1000, the *1212 number would be the callerID. This also applies to IM account names; if IM account 'tropocloud' sends a message to 'foobar123', the callerID would be 'tropocloud'.

	The callerID can be manually set to a specific number; for voice calls, this can be any valid phone number, though for SMS and IM it must be a number/ID assigned to your account.

* channel

	Channel tells Tropo whether the call is "voice" or "text".

* network

	Network is used mainly by the text channels; values can be SMS when sending a text message, or a valid IM network name such as AIM, GTALK, MSN, JABBER, TWITTER and YAHOO. For IM network, you must have an IM account linked in your app. For example, if you try to send to AIM when you don't have an AIM username included in your app, your app will fail.

* timeout

	Timeout only applies to the voice channel and determines the amount of time Tropo will wait - in seconds - for the call to be answered before giving up.

* tropo_tag

	An arbitrary unique identifier that you may use to identify the call once it is placed and passed to your AGI server. This value will appear in the tropo\_headers variable received at the beginning of the request to your AGI server in the JSON as tropo\_tag.
	
You may then invoke a call request via HTTP as follows:

* GET
<pre>
	http://api.tropo.com/1.0/sessions?action=create&token=TOKEN&destination=NUMBER&caller\_id=CALLINGNUMBER&tropo_tag=1234
</pre>

* POST
<pre>
	http://api.tropo.com/1.0/sessions
	<code>
	<session>
		<token>YOUR_TOKEN</token>
		<var name="destination" value="4155551212" />
		<var name="caller_id" value="7146432997" />
		<var name="tropo_tag" value=1234 />
	</session>
	</code>
</pre>
	
Supported Adhearsion & AGI Methods
----------------------------------

Refer to the wiki [Supported Adhearsion and Asterisk Gateway Interface (AGI) Commands](http://github.com/tropo/tropo-agitate/wiki/Supported-Adhearsion-&-AGI-Methods) page.

Asterisk Sound Files Available
------------------------------

Refer to the wiki [Asterisk Core Sounds Available](http://github.com/tropo/tropo-agitate/wiki/Built-In-Asterisk-Sound-Files) page.

Adhearsion Dialplan Examples
----------------------------

These Adhearsion dialplan examples are also available in the 'examples' directory of this project.

<pre>
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
	
	# Shows how to set the voice option for speech synthesis/TTS
	set_voice_example {
	  play 'Hello world!'
	  execute "voice", "simon"
	  play 'Hello world!'
	  execute "voice", "default"
	  play 'Hello world!'
	}

	# Shows how to set the voice option for speech synthesis/TTS
	set_recognizer_example {
	  execute "voice", "carmen"
	  execute "recognizer", "es-es"
	  result = execute 'ask', { :prompt  => 'Por favor, ingrese su código postal', 
	                            :choices => 'zipcode([5 DIGITS])' }.to_json
	  # Get rid of the '200 result =' and then parse the JSON
	  response = JSON.parse(result[11..-1])
	  ahn_log.debug response
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
</pre>
