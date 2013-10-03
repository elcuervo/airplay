require "airplay"

module Airplay
  module CLI
    class << self
      def list
        Airplay.nodes.each do |node|
          puts "* #{node.name} - #{node.ip}"
        end
      end

      def play(video, options)
        node = options[:node]
        player = node.play(video)
        player.wait
      end

      def view(file_or_dir, options)
        node = options[:node]
        wait = options[:wait]

        if File.directory?(file_or_dir)
          Dir.glob("#{file_or_dir}/*").each do |file|
            view_image(node, file)
            sleep wait
          end
        else
          view_image(node, file_or_dir)
          sleep
        end
      end

      private

      def view_image(node, image)
        node.view(image, transition: "SlideLeft")
      end
    end
  end
end
