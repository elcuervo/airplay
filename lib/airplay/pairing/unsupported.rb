require "airplay/errors"

module Airplay
  module Pairing
    # Public: Names the authentication mechanisms this build defers.
    module Unsupported
      MECHANISMS = {
        "fp-setup" => "FairPlay",
        "auth-setup" => "MFi",
        "accessory" => "HAP accessory mode"
      }.freeze

      class << self
        # Public: Raises when a receiver demands one of the deferred mechanisms.
        def check!(value)
          return true if value.nil? || value.empty?

          mechanism = MECHANISMS.fetch(value.to_s, value.to_s)
          raise Airplay::UnsupportedError.new(
            "this device requires #{mechanism}, which this build does not implement",
            code: :unsupported_feature
          )
        end
      end
    end
  end
end
