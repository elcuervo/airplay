require "integration_helper"
require "net/http"

scope 'Setting a persistent connection' do
  test do
    connection = Airplay::Connection::Persistent.new(SERVER_URL)
    req = Net::HTTP::Get.new("#{SERVER_URL}/server-info")

    assert !!connection.mac_address
    assert connection.alive?

    connection.queue << req

    assert connection.working?
    sleep 1 while connection.working?
    connection.close

    assert !connection.alive?
  end
end
