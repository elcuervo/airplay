require "openssl"

module Airplay
  module Pairing
    # Public: HKDF-SHA512 expansion for channel keys.
    module HKDF
      class << self
        def expand(shared_secret, salt:, info:, length: 32)
          OpenSSL::KDF.hkdf(
            shared_secret.to_s.b,
            salt: salt.to_s.b,
            info: info.to_s.b,
            length: length,
            hash: "SHA512"
          )
        end

        def control_keys(shared_secret)
          [
            expand(shared_secret, salt: "Control-Salt", info: "Control-Write-Encryption-Key"),
            expand(shared_secret, salt: "Control-Salt", info: "Control-Read-Encryption-Key")
          ]
        end

        def event_keys(shared_secret)
          [
            expand(shared_secret, salt: "Events-Salt", info: "Events-Write-Encryption-Key"),
            expand(shared_secret, salt: "Events-Salt", info: "Events-Read-Encryption-Key")
          ]
        end
      end
    end
  end
end
