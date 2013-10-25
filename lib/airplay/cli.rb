require "ruby-progressbar"
require "airplay"
require "airplay/cli/image_viewer"

# Public: Airplay core module
#
module Airplay
  # Public: Airplay CLI module
  #
  module CLI
    class << self
      # Public: Lists all the devices to STDOUT
      #
      # Returns nothing.
      #
      def list
        Airplay.devices.each do |device|
          puts <<-EOS.gsub(/^\s{12}/,'')
            * #{device.name} (#{device.info.model} running #{device.info.os_version})
              ip: #{device.ip}
              resolution: #{device.info.resolution}

          EOS
        end
      end

      # Public: Plays a video given a device
      #
      # video   - The url or file path to the video
      # options - Options that include the device
      #           * device: The device in which it should run
      #
      # Returns nothing.
      #
      def play(video, options)
        device = options[:device]
        player = device.play(video)
        puts "Playing #{video}"
        bar = ProgressBar.create(
          title: device.name,
          format: "%a [%B] %p%% %t"
        )

        player.progress -> playback {
          bar.progress = playback.percent if playback.percent
        }

        player.wait
      end

      # Public: Show an image given a device
      #
      # file_or_dir - The url, file path or folder path to the image/s
      # options     - Options that include the device
      #               * device: The device in which it should run
      #               * interactive: Boolean flag to control playback with the
      #                              arrow keys
      #
      # Returns nothing.
      #
      def view(file_or_dir, options)
        device = options[:device]
        viewer = ImageViewer.new(device, options)

        if File.directory?(file_or_dir)
          files = Dir.glob("#{file_or_dir}/*")

          if options[:interactive]
            viewer.interactive(files)
          else
            viewer.slideshow(files)
          end
        else
          viewer.view(file_or_dir)
          sleep
        end
      end

    end
  end
end
