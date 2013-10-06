require 'action_dispatch/routing/route_set'

class ActionDispatch::Routing::RouteSet
  def eval_block(block) #:nodoc:
    # I tried overriding this in a module, but for some reason the overriden
    # method is not invoked, so for now this method contains the original rails
    # code.
    if block.arity == 1
      raise "You are using the old router DSL which has been removed in Rails 3.1. " <<
        "Please check how to update your routes file at: http://www.engineyard.com/blog/2010/the-lowdown-on-routes-in-rails-3/"
    end
    mapper = ActionDispatch::Routing::Mapper.new(self)
    if default_scope
      mapper.with_default_scope(default_scope, &block)
    else
      mapper.instance_exec(&block)
    end

    # Reuse the block definition for the menu mapper.
    mapper = ActionDispatch::Menu::Mapper.new(self)
    if default_scope
      mapper.with_default_scope(default_scope, &block)
    else
      mapper.instance_exec(&block)
    end
  end
end
