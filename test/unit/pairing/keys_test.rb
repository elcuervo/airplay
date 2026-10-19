require "test_helper"
require "airplay/pairing/keys"

# RFC 7748 section 6.1 (X25519) and RFC 8032 section 7.1 test 1 (Ed25519).
class KeysTest < Minitest::Test
  X25519_ALICE_PRIVATE = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
  X25519_ALICE_PUBLIC = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
  X25519_BOB_PRIVATE = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
  X25519_BOB_PUBLIC = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"
  X25519_SHARED = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

  ED25519_PRIVATE = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  ED25519_PUBLIC = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  ED25519_MESSAGE = "".b
  ED25519_SIGNATURE = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" \
                      "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

  def test_x25519_raw_private_derives_the_rfc_public_key
    key = Airplay::Pairing::Keys.x25519_private(hex(X25519_ALICE_PRIVATE))

    assert_equal X25519_ALICE_PUBLIC, Airplay::Pairing::Keys.raw_public(key).unpack1("H*")
  end

  def test_x25519_shared_secret_matches_the_rfc_vector
    alice = Airplay::Pairing::Keys.x25519_private(hex(X25519_ALICE_PRIVATE))
    bob = Airplay::Pairing::Keys.x25519_private(hex(X25519_BOB_PRIVATE))

    assert_equal X25519_SHARED, alice.derive(Airplay::Pairing::Keys.x25519_public(hex(X25519_BOB_PUBLIC))).unpack1("H*")
    assert_equal X25519_SHARED, bob.derive(Airplay::Pairing::Keys.x25519_public(hex(X25519_ALICE_PUBLIC))).unpack1("H*")
  end

  def test_x25519_raw_keys_round_trip
    assert_equal X25519_ALICE_PRIVATE, round_trip(X25519_ALICE_PRIVATE, :x25519)
    assert_equal X25519_BOB_PRIVATE, round_trip(X25519_BOB_PRIVATE, :x25519)
  end

  def test_ed25519_raw_private_derives_the_rfc_public_key
    key = Airplay::Pairing::Keys.ed25519_private(hex(ED25519_PRIVATE))

    assert_equal ED25519_PUBLIC, Airplay::Pairing::Keys.raw_public(key).unpack1("H*")
  end

  def test_ed25519_known_signature_verifies_with_the_raw_public_key
    key = Airplay::Pairing::Keys.ed25519_private(hex(ED25519_PRIVATE))
    public_key = Airplay::Pairing::Keys.ed25519_public(hex(ED25519_PUBLIC))

    assert_equal ED25519_SIGNATURE, key.sign(nil, ED25519_MESSAGE).unpack1("H*")
    assert public_key.verify(nil, hex(ED25519_SIGNATURE), ED25519_MESSAGE)
  end

  def test_ed25519_raw_keys_round_trip
    assert_equal ED25519_PRIVATE, round_trip(ED25519_PRIVATE, :ed25519)
  end

  def test_a_non_raw_key_length_is_rejected
    assert_raises(Airplay::ProtocolError) { Airplay::Pairing::Keys.x25519_public("\x01" * 31) }
    assert_raises(Airplay::ProtocolError) { Airplay::Pairing::Keys.ed25519_private("\x01" * 33) }
  end

  private

  def hex(value) = [value].pack("H*")

  def round_trip(raw, type)
    key = Airplay::Pairing::Keys.public_send(:"#{type}_private", hex(raw))

    Airplay::Pairing::Keys.raw_private(key).unpack1("H*")
  end
end
