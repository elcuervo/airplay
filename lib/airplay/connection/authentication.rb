require "net/http/digest_auth"

module Airplay
  class Connection
    Authentication = Struct.new(:device, :handler) do
      def sign(request)
        auth_token = authenticate(request)
        request.add_field('Authorization', auth_token) if auth_token
        request
      end

      private

      def uri(request)
        path = "http://#{device.address}#{request.path}"
        uri = URI.parse(path)
        uri.user = "Airplay"
        uri.password = device.password

        uri
      end

      def authenticate(request)
        response = handler.request(request)

        auth = response["www-authenticate"] || response["WWW-Authenticate"]
        digest_authentication(request, auth) if auth
      end

      def digest_authentication(request, auth)
        digest = Net::HTTP::DigestAuth.new
        digest.auth_header(uri(request), auth, request.method)
      end
    end
  end
end
