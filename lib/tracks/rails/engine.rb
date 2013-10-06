require "rails/engine"

require "tracks/rails/action_dispatch/menu"

module Tracks
  # Extensions of the rails engine class
  module Rails
    module Engine
      def menu
        @menu ||= ActionDispatch::Menu::LinkSet.new
      end
    end
  end
end

class ::Rails::Engine
  include Tracks::Rails::Engine
end
