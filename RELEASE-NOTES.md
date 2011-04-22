Tropo AGItate - Release Notes
=============================

v0.1.7
------

* Add framework for "magic" channel variables. This supports things like CALLERID(all) vs. CALLERID(name) vs. CALLERID(num) that all have overlap in Asterisk. We now try to do the right thing when setting or reading each variation. More special variables can be easily added.
* Enhanced Dial compatibility: Allow setting the CallerID on outbound calls, set DIALSTATUS based on Tropo response
and clean up parsing of dial string
* Set the default AGI port if unspecified in the YAML
* Update to RSpec 2
* Allow detecting the Tropo dialed number for incoming calls (agi_dnid)
* Fix fatal missing error on SIP failover failure
* Update unit tests for new functionality; fix broken unit tests