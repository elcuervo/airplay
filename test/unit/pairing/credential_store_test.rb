require "test_helper"
require "tmpdir"

class CredentialStoreTest < Minitest::Test
  def test_records_are_private_outside_the_repository_and_written_atomically
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)
      record = { "device" => "device-1", "identifier" => "pair-id", "permissions" => 1 }

      assert store.unpaired?("device-1")
      store.write(record)

      assert_equal 0o700, File.stat(dir).mode & 0o777
      assert_equal 0o600, File.stat(store.path_for("device-1")).mode & 0o777
      assert_equal ["device-1.plist"], Dir.children(dir)
      assert_equal record, store.read("device-1")
      refute store.unpaired?("device-1")
    end
  end

  def test_a_record_round_trips_every_plist_type
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)
      record = {
        "device" => "device-2",
        "data" => Airplay::Plist::Data.new("\x00\xFF\x01".b),
        "date" => Time.utc(2026, 10, 19),
        "nested" => { "list" => [1, true, "x"] },
        "permissions" => 1
      }

      store.write(record)

      assert_equal record, store.read("device-2")
      assert_nil store.read("unknown")
      assert store.unpaired?("unknown")
    end
  end

  def test_a_repository_path_is_refused
    error = assert_raises(Airplay::ConfigurationError) do
      Airplay::Pairing::CredentialStore.new(directory: File.join(Dir.pwd, "credentials"))
    end

    assert_equal :insecure_credentials_path, error.code
  end

  def test_an_unsafe_device_identifier_is_refused
    Dir.mktmpdir do |dir|
      store = Airplay::Pairing::CredentialStore.new(directory: dir)

      error = assert_raises(Airplay::ConfigurationError) do
        store.write("device" => "../escape")
      end

      assert_equal :invalid_credential_id, error.code
      assert_empty Dir.children(dir)
    end
  end

  def test_the_default_directory_follows_the_xdg_config_home
    Dir.mktmpdir do |dir|
      with_env("XDG_CONFIG_HOME" => dir, "AIRPLAY_CREDENTIALS_DIR" => nil) do
        store = Airplay::Pairing::CredentialStore.new
        assert_equal File.join(dir, "airplay", "devices"), store.directory
      end
    end
  end

  def test_the_environment_override_wins
    Dir.mktmpdir do |dir|
      with_env("AIRPLAY_CREDENTIALS_DIR" => dir) do
        assert_equal dir, Airplay::Pairing::CredentialStore.new.directory
      end
    end
  end

  private

  def with_env(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    yield
  ensure
    previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
