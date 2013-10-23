require "airplay"
require "airplay/cli/image_viewer"

require "ruby-progressbar"

module Airplay
  module CLI
    class << self
      def list
        Airplay.devices.each do |device|
          puts <<-EOS.gsub(/^\s{12}/,'')
            * #{device.name} (#{device.info.model} running #{device.info.os_version})
              ip: #{device.ip}
              resolution: #{device.info.resolution}

          EOS
        end
      end

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
