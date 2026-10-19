require "fileutils"
require "tempfile"

require "airplay/errors"
require "airplay/plist"

module Airplay
  module Pairing
    # Public: Per-device pairing records under a private directory outside the repository.
    class CredentialStore
      ENV_KEY = "AIRPLAY_CREDENTIALS_DIR"
      REPOSITORY = File.expand_path("../../..", __dir__).freeze
      DIRECTORY_MODE = 0o700
      FILE_MODE = 0o600
      SAFE_IDENTIFIER = /\A[A-Za-z0-9_.-]+\z/

      attr_reader :directory

      def initialize(directory: nil)
        @directory = File.expand_path(directory || ENV[ENV_KEY] || default_directory)
        refuse_repository_path!
      end

      def read(device)
        path = path_for(device)
        Airplay::Plist.load(File.binread(path)) if File.exist?(path)
      end

      def write(record)
        FileUtils.mkdir_p(@directory)
        File.chmod(DIRECTORY_MODE, @directory)

        Tempfile.create(["credential", ".plist"], @directory) do |file|
          file.binmode
          file.write(Airplay::Plist.dump(record))
          file.chmod(FILE_MODE)
          file.flush
          File.rename(file.path, path_for(record.fetch("device")))
        end

        record
      end

      def delete(device)
        File.unlink(path_for(device))
        true
      rescue Errno::ENOENT
        false
      end

      def unpaired?(device)
        !File.exist?(path_for(device))
      end

      def path_for(device)
        File.join(@directory, "#{safe(device)}.plist")
      end

      def self.key_for(device)
        device.to_s.gsub(/[^A-Za-z0-9_.-]/, "_")
      end

      def key_for(device)
        self.class.key_for(device)
      end

      private

      def safe(device)
        name = device.to_s
        unless SAFE_IDENTIFIER.match?(name) && !%w[. ..].include?(name)
          raise Airplay::ConfigurationError.new("unsafe device identifier #{name.inspect}",
                                                code: :invalid_credential_id)
        end

        name
      end

      def refuse_repository_path!
        prefix = REPOSITORY + File::SEPARATOR
        return unless @directory == REPOSITORY || @directory.start_with?(prefix)

        raise Airplay::ConfigurationError.new("credential directory must be outside the repository",
                                              code: :insecure_credentials_path)
      end

      def default_directory
        base = ENV["XDG_CONFIG_HOME"] || File.join(Dir.home, ".config")
        File.join(base, "airplay", "devices")
      end
    end
  end
end
