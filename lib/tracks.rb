require "tracks/engine"

module Tracks
  module Rails
    autoload :Engien, "tracks/rails/engine"
  end
end

require "tracks/routing"

require "tracks/rails/engine"
require "tracks/rails/action_dispatch/routing/route_set"
