require 'dnssd'
require 'net/http'
require 'net/http/persistent'
require 'net/http/digest_auth'
require 'uri'

module Airplay end
require 'airplay/server'
require 'airplay/server/node'
require 'airplay/server/browser'
require 'airplay/server/features'

require 'airplay/protocol'
require 'airplay/protocol/image'
require 'airplay/protocol/media'
require 'airplay/protocol/scrub'

require 'airplay/client'
