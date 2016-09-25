require "integration_helper"
require "net/http"

scope 'Setting a persistent connection' do
  test do
    connection = Airplay::Connection::Persistent.new(SERVER_URL)
    req = Net::HTTP::Get.new("/server-info")

    assert !!connection.mac_address
    assert connection.alive?

    res = connection.request(req)

    connection.close
    assert !connection.alive?
  end
end
