require 'dnssd'
require 'net/http'
require 'net/http/digest_auth'
require 'uri'

module Airplay; end;
require 'airplay/server'
require 'airplay/server/browser'
require 'airplay/server/node'

require 'airplay/protocol'
require 'airplay/protocol/image'
require 'airplay/protocol/video'
require 'airplay/protocol/scrub'

require 'airplay/client'
