module Airplay
  module CLI
    class ImageViewer
      attr_reader :options, :devices

      def initialize(devices, options = {})
        @devices = Array(devices)
        @options = options
      end

      def view(file, transition = "SlideLeft")
        puts "Showing #{file}"
        devices.each do |device|
          device.view(file, transition: transition)
        end
      end

      def slideshow(files)
        puts "Autoplay every #{options[:wait]}"
        files.each do |file|
          view(file)
          sleep options[:wait]
        end
      end

      def interactive(files)
        numbers = Array(0...files.count)
        transition = "None"

        i = 0
        loop do
          view(files[i], transition)

          case read_char
          when "\e[C" # Right Arrow
            i = i + 1 > numbers.count - 1 ? 0 : i + 1
            transition = "SlideLeft"
          when "\e[D" # Left Arrow
            i = i - 1 < 0 ? numbers.count - 1 : i - 1
            transition = "SlideRight"
          else
            break
          end
        end
      end

      private

      def read_char
        STDIN.echo = false
        STDIN.raw!

        input = STDIN.getc.chr
        if input == "\e" then
          input << STDIN.read_nonblock(3) rescue nil
          input << STDIN.read_nonblock(2) rescue nil
        end
      ensure
        STDIN.echo = true
        STDIN.cooked!

        return input
      end

    end
  end
end
