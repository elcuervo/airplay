require "ruby-progressbar"
require "airplay"
require "airplay/cli/image_viewer"
require "airplay/cli/doctor"

# Public: Airplay core module
#
module Airplay
  # Public: Airplay CLI module
  #
  module CLI
    class << self
      # Public: Shows CLI help
      #
      # Returns nothing.
      #
      def help
        Airplay.configuration.load

        puts <<-EOS.gsub!(" "*10, "")
          Usage: air [OPTIONS] ACTION [URL OR PATH]

          Command line for the apple tv.
          Example: air play my_video.mov

          Actions:

          list    - Lists the available devices in the network.
          help    - This help.
          version - The current airplay-cli version.
          play    - Plays a local or remote video.
          view    - Shows an image or a folder of images, can be an url.
          doctor  - Shows some debug information to trace bugs.

          Options:

          --device      - Name of the device where it should be played (Default: The first one)
          --wait        - The wait time for playing an slideshow (Default: 3)
          --interactive - Control the slideshow using left and right arrows.
          --password    - Adds the device password
          --url         - Allows you to specify an Apple TV url

        EOS
      end

      # Public: Lists all the devices to STDOUT
      #
      # Returns nothing.
      #
      def list
        Airplay.devices.each do |device|
          puts <<-EOS.gsub(/^\s{12}/,'')
            * #{device.name} (#{device.info.model} running #{device.info.os_version})
              ip: #{device.ip}
              mac: #{device.id}
              password?: #{device.password? ? "yes" : "no"}
              type: #{device.type}
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
        password = options[:password]
        url = options[:url]

        Airplay.devices.add("Apple TV", url) if url
        device.password = password if password

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

      def doctor
        puts <<-EOS.gsub!(" "*10, "")

          This will run some basic tests on your network trying to find errors
          and debug information to help fix them.

        EOS

        who = Airplay::CLI::Doctor.new

        puts "Running dns-sd tests:"
        who.information
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
        password = options[:password]
        url = options[:url]

        if url
          Airplay.configure { |c| c.autodiscover = false }
          device = Airplay.devices.add("Apple TV", url)
        end
        device.password = password if password

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

      # Public: Shows the current CLI version
      #
      # Returns nothing
      #
      def version
        Airplay.configuration.load
        v = Airplay::CLI::VERSION
        puts <<-EOS

                            i@@@@@@@@@@@@@@@@@@@@@@@@@
                          i80000000000000000000000000000
                        i80000000000000000000000000000000G
                      i8000000000000000000000000000000000000
                    i80000000000000000000000000000000000000000
            @00000    @0000000000000000000000000000000000000@   000000@
            @0000008    @000000000000000000000000000000000@   80000000@
            @001          @00000000000000000000000000000@          100@
            @001            @0000000000000000000000000@            100@
            @001              80000000000000000000008              t00@
            @001                8000000000000000008                t00@
            @001                  800000000000008                  t00@
            @001                    G000000000G                    t00@
            @001                      G00000G                      t00@
            @001                        L0L                        t00@
            @001                                                   t00@
            @001                        air                        t00@
            @001                       #{v}                       t00@
            @001                                                   t00@
            @001                                                   t00@
            @001                                                   100@
            @00000000000000000000000000000000000000000000000000000G000@
            @000000000000000000000000000000000000000000000000000000000@

        EOS
      end

    end
  end
end
