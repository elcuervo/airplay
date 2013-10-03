require "airplay"

module Airplay
  module CLI
    class << self
      def list
        Airplay.nodes.each do |node|
          puts "* #{node.name} - #{node.ip}"
        end
      end

      def view(file_or_dir, node = Airplay.nodes.first)
        if File.directory?(file_or_dir)
          Dir.glob("#{file_or_dir}/*").each do |file|
            puts file
            puts view_image(node, file)
            sleep 2
          end
        else
          view_image(node, file_or_dir)
        end
        sleep
      end

      private

      def view_image(node, image)
        node.view(image, transition: "SlideLeft")
      end
    end
  end
end
