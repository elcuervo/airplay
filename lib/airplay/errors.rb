module Airplay
  # Public: Base error carrying a stable machine-readable code.
  class Error < StandardError
    class << self
      def code
        :airplay_error
      end
    end

    attr_reader :code, :device

    def initialize(message = nil, code: self.class.code, device: nil)
      @code = code
      @device = device
      super(message || code.to_s)
    end

    # Public: Attaches the device identity once, returning the error.
    def with_device(value)
      @device ||= value
      self
    end
  end

  class TransportError < Error
    def self.code = :transport_error
  end

  class TimeoutError < TransportError
    def self.code = :timeout
  end

  class ProtocolError < Error
    def self.code = :protocol_error
  end

  class AuthenticationError < Error
    def self.code = :authentication_error
  end

  class AuthRequiredError < AuthenticationError
    def self.code = :auth_required
  end

  class AuthFailedError < AuthenticationError
    def self.code = :auth_failed
  end

  class PlaybackError < Error
    def self.code = :playback_error
  end

  class TimingError < Error
    def self.code = :timing_error
  end

  class ConfigurationError < Error
    def self.code = :configuration_error
  end

  class SessionClosedError < Error
    def self.code = :session_closed
  end

  class UnsupportedError < Error
    def self.code = :unsupported
  end
end
