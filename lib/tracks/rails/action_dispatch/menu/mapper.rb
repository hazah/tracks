module ActionDispatch
  module Menu
    class Mapper
      URL_OPTIONS = [:protocol, :subdomain, :domain, :host, :port]
      SCOPE_OPTIONS = [:path, :shallow_path, :as, :shallow_prefix, :module,
                       :controller, :action, :path_names, :constraints,
                       :shallow, :blocks, :defaults, :options]

      def self.normalize_path(path)
        path = Journey::Router::Utils.normalize_path(path)
        path.gsub!(%r{/(\(+)/?}, '\1/') unless path =~ %r{^/\(+[^)]+\)$}
        path
      end

      def self.normalize_name(name)
        normalize_path(name)[1..-1].tr("/", "_")
      end

      module Base
        def root(options = {})
          match '/', { :as => :root, :via => :get }.merge!(options)
        end

        def match(path, options=nil)
        end

        def mount(app, options = nil)
          if options
            path = options.delete(:at)
          else
            unless Hash === app
              raise ArgumentError, "must be called with mount point"
            end

            options = app
            app, path = options.find { |k, _| k.respond_to?(:call) }
            options.delete(app) if app
          end

          raise "A rack application must be specified" unless path

          options[:as] ||= app_name(app)
          options[:via] ||= :all

          match(path, options.merge(:to => app, :anchor => false, :format => false))

          define_generate_prefix(app, options[:as])
          self
        end

        def default_url_options=(options)
          @set.default_url_options = options
        end
        alias_method :default_url_options, :default_url_options=

        def with_default_scope(scope, &block)
          scope(scope) do
            instance_exec(&block)
          end
        end

        private
          def app_name(app)
            return unless app.respond_to?(:routes)

            if app.respond_to?(:railtie_name)
              app.railtie_name
            else
              class_name = app.class.is_a?(Class) ? app.name : app.class.name
              ActiveSupport::Inflector.underscore(class_name).tr("/", "_")
            end
          end

          def define_generate_prefix(app, name)
#            return unless app.respond_to?(:routes) && app.routes.respond_to?(:define_mounted_helper)

#            _route = @set.named_routes.routes[name.to_sym]
#            _routes = @set
#            app.routes.define_mounted_helper(name)
#            app.routes.singleton_class.class_eval do
#              define_method :mounted? do
#                true
#              end

#              define_method :_generate_prefix do |options|
#                prefix_options = options.slice(*_route.segment_keys)
#                # we must actually delete prefix segment keys to avoid passing them to next url_for
#                _route.segment_keys.each { |k| options.delete(k) }
#                _routes.url_helpers.send("#{name}_path", prefix_options)
#              end
#            end
          end
      end

      module HttpHelpers
        def get(*args, &block)
          map_method(:get, args, &block)
        end
        def post(*args, &block)
          map_method(:post, args, &block)
        end
         def patch(*args, &block)
          map_method(:patch, args, &block)
        end
        def put(*args, &block)
          map_method(:put, args, &block)
        end
        def delete(*args, &block)
          map_method(:delete, args, &block)
        end

        private
          def map_method(method, args, &block)
            options = args.extract_options!
            options[:via] = method
            match(*args, options, &block)
            self
          end
      end
      module Scoping
        def scope(*args)
          options = args.extract_options!.dup
          recover = {}

          options[:path] = args.flatten.join('/') if args.any?
          options[:constraints] ||= {}

          if options[:constraints].is_a?(Hash)
            defaults = options[:constraints].select do
              |k, v| URL_OPTIONS.include?(k) && (v.is_a?(String) || v.is_a?(Fixnum))
            end

            (options[:defaults] ||= {}).reverse_merge!(defaults)
          else
            block, options[:constraints] = options[:constraints], {}
          end

          SCOPE_OPTIONS.each do |option|
            if option == :blocks
              value = block
            elsif option == :options
              value = options
            else
              value = options.delete(option)
            end

            if value
              recover[option] = @scope[option]
              @scope[option] = send("merge_#{option}_scope", @scope[option], value)
            end
          end

          yield
          self
        ensure
          @scope.merge!(recover)
        end
        def controller(controller, options={})
          options[:controller] = controller
          scope(options) { yield }
        end
        def namespace(path, options = {})
          path = path.to_s
          options = { :path => path, :as => path, :module => path,
                      :shallow_path => path, :shallow_prefix => path }.merge!(options)
          scope(options) { yield }
        end
        def constraints(constraints = {})
          scope(:constraints => constraints) { yield }
        end
        def defaults(defaults = {})
          scope(:defaults => defaults) { yield }
        end
        private
          def merge_path_scope(parent, child) #:nodoc:
            Mapper.normalize_path("#{parent}/#{child}")
          end

          def merge_shallow_path_scope(parent, child) #:nodoc:
            Mapper.normalize_path("#{parent}/#{child}")
          end

          def merge_as_scope(parent, child) #:nodoc:
            parent ? "#{parent}_#{child}" : child
          end

          def merge_shallow_prefix_scope(parent, child) #:nodoc:
            parent ? "#{parent}_#{child}" : child
          end

          def merge_module_scope(parent, child) #:nodoc:
            parent ? "#{parent}/#{child}" : child
          end

          def merge_controller_scope(parent, child) #:nodoc:
            child
          end

          def merge_action_scope(parent, child) #:nodoc:
            child
          end

          def merge_path_names_scope(parent, child) #:nodoc:
            merge_options_scope(parent, child)
          end

          def merge_constraints_scope(parent, child) #:nodoc:
            merge_options_scope(parent, child)
          end

          def merge_defaults_scope(parent, child) #:nodoc:
            merge_options_scope(parent, child)
          end

          def merge_blocks_scope(parent, child) #:nodoc:
            merged = parent ? parent.dup : []
            merged << child if child
            merged
          end

          def merge_options_scope(parent, child) #:nodoc:
            (parent || {}).except(*override_keys(child)).merge!(child)
          end

          def merge_shallow_scope(parent, child) #:nodoc:
            child ? true : false
          end

          def override_keys(child) #:nodoc:
            child.key?(:only) || child.key?(:except) ? [:only, :except] : []
          end
      end
      module Resources
        VALID_ON_OPTIONS = [:new, :collection, :member]
        RESOURCE_OPTIONS = [:as, :controller, :path, :only, :except, :param, :concerns]
        CANONICAL_ACTIONS = %w(index create new show update destroy)
        RESOURCE_METHOD_SCOPES = [:collection, :member, :new]
        RESOURCE_SCOPES = [:resource, :resources]

        class Resource #:nodoc:
          attr_reader :controller, :path, :options, :param

          def initialize(entities, options = {})
            @name = entities.to_s
            @path = (options[:path] || @name).to_s
            @controller = (options[:controller] || @name).to_s
            @as = options[:as]
            @param = (options[:param] || :id).to_sym
            @options = options
          end

          def default_actions
            [:index, :create, :new, :show, :update, :destroy, :edit]
          end

          def actions
            if only = @options[:only]
              Array(only).map(&:to_sym)
            elsif except = @options[:except]
              default_actions - Array(except).map(&:to_sym)
            else
              default_actions
            end
          end

          def name
            @as || @name
          end

          def plural
            @plural ||= name.to_s
          end

          def singular
            @singular ||= name.to_s.singularize
          end

          alias :member_name :singular

          # Checks for uncountable plurals, and appends "_index" if the plural
          # and singular form are the same.
          def collection_name
            singular == plural ? "#{plural}_index" : plural
          end

          def resource_scope
            { :controller => controller }
          end

          alias :collection_scope :path

          def member_scope
            "#{path}/:#{param}"
          end

          alias :shallow_scope :member_scope

          def new_scope(new_path)
            "#{path}/#{new_path}"
          end

          def nested_param
            :"#{singular}_#{param}"
          end

          def nested_scope
            "#{path}/:#{nested_param}"
          end

        end

        class SingletonResource < Resource #:nodoc:
          def initialize(entities, options)
            super
            @as = nil
            @controller = (options[:controller] || plural).to_s
            @as = options[:as]
          end

          def default_actions
            [:show, :create, :update, :destroy, :new, :edit]
          end

          def plural
            @plural ||= name.to_s.pluralize
          end

          def singular
            @singular ||= name.to_s
          end

          alias :member_name :singular
          alias :collection_name :singular

          alias :member_scope :path
          alias :nested_scope :path
        end

        def resources_path_names(options)
          @scope[:path_names].merge!(options)
        end
        def resource(*resources, &block)
          options = resources.extract_options!.dup

          if apply_common_behavior_for(:resource, resources, options, &block)
            return self
          end

          resource_scope(:resource, SingletonResource.new(resources.pop, options)) do
            yield if block_given?

            concerns(options[:concerns]) if options[:concerns]

            collection do
              post :create
            end if parent_resource.actions.include?(:create)

            new do
              get :new
            end if parent_resource.actions.include?(:new)

            set_member_mappings_for_resource
          end

          self
        end
        def resources(*resources, &block)
          options = resources.extract_options!.dup

          if apply_common_behavior_for(:resources, resources, options, &block)
            return self
          end

          resource_scope(:resources, Resource.new(resources.pop, options)) do
            yield if block_given?

            concerns(options[:concerns]) if options[:concerns]

            collection do
              get :index if parent_resource.actions.include?(:index)
              post :create if parent_resource.actions.include?(:create)
            end

            new do
              get :new
            end if parent_resource.actions.include?(:new)

            set_member_mappings_for_resource
          end

          self
        end
        def collection
          unless resource_scope?
            raise ArgumentError, "can't use collection outside resource(s) scope"
          end

          with_scope_level(:collection) do
            scope(parent_resource.collection_scope) do
              yield
            end
          end
        end
         def member
          unless resource_scope?
            raise ArgumentError, "can't use member outside resource(s) scope"
          end

          with_scope_level(:member) do
            scope(parent_resource.member_scope) do
              yield
            end
          end
        end

        def new
          unless resource_scope?
            raise ArgumentError, "can't use new outside resource(s) scope"
          end

          with_scope_level(:new) do
            scope(parent_resource.new_scope(action_path(:new))) do
              yield
            end
          end
        end

        def nested
          unless resource_scope?
            raise ArgumentError, "can't use nested outside resource(s) scope"
          end

          with_scope_level(:nested) do
            if shallow?
              with_exclusive_scope do
                if @scope[:shallow_path].blank?
                  scope(parent_resource.nested_scope, nested_options) { yield }
                else
                  scope(@scope[:shallow_path], :as => @scope[:shallow_prefix]) do
                    scope(parent_resource.nested_scope, nested_options) { yield }
                  end
                end
              end
            else
              scope(parent_resource.nested_scope, nested_options) { yield }
            end
          end
        end

        # See ActionDispatch::Routing::Mapper::Scoping#namespace
        def namespace(path, options = {})
          if resource_scope?
            nested { super }
          else
            super
          end
        end

        def shallow
          scope(:shallow => true, :shallow_path => @scope[:path]) do
            yield
          end
        end

        def shallow?
          parent_resource.instance_of?(Resource) && @scope[:shallow]
        end

        # match 'path' => 'controller#action'
        # match 'path', to: 'controller#action'
        # match 'path', 'otherpath', on: :member, via: :get
        def match(path, *rest)

          if rest.empty? && Hash === path
            options = path
            path, to = options.find { |name, _value| name.is_a?(String) }
            options[:to] = to
            options.delete(path)
            paths = [path]
          else
            options = rest.pop || {}
            paths = [path] + rest
          end

          options[:anchor] = true unless options.key?(:anchor)

          if options[:on] && !VALID_ON_OPTIONS.include?(options[:on])
            raise ArgumentError, "Unknown scope #{on.inspect} given to :on"
          end

          if @scope[:controller] && @scope[:action]
            options[:to] ||= "#{@scope[:controller]}##{@scope[:action]}"
          end

          paths.each do |_path|
            menu_options = options.dup
            menu_options[:path] ||= _path if _path.is_a?(String)

            path_without_format = _path.to_s.sub(/\(\.:format\)$/, '')
            if using_match_shorthand?(path_without_format, menu_options)
              menu_options[:to] ||= path_without_format.gsub(%r{^/}, "").sub(%r{/([^/]*)$}, '#\1')
            end

            decomposed_match(_path, menu_options)
          end
          self
        end

        def using_match_shorthand?(path, options)
          path && (options[:to] || options[:action]).nil? && path =~ %r{/[\w/]+$}
        end

        def decomposed_match(path, options) # :nodoc:
          if on = options.delete(:on)
            send(on) { decomposed_match(path, options) }
          else
            case @scope[:scope_level]
            when :resources
              nested { decomposed_match(path, options) }
            when :resource
              member { decomposed_match(path, options) }
            else
              add_menu_item(path, options)
            end
          end
        end

        def add_menu_item(action, options) # :nodoc:
          path = path_for_action(action, options.delete(:path))
          action = action.to_s.dup

          if action =~ /^[\w\/]+$/
            options[:action] ||= action unless action.include?("/")
          else
            action = nil
          end
          if !options.fetch(:as, true)
            options.delete(:as)
          else
            options[:as] = name_for_action(options[:as], action)
          end

#          mapping = Mapping.new(@set, @scope, URI.parser.escape(path), options)
#          app, conditions, requirements, defaults, as, anchor = mapping.to_route
#          @set.add_route(app, conditions, requirements, defaults, as, anchor)
        end

        def root(path, options={})
          if path.is_a?(String)
            options[:to] = path
          elsif path.is_a?(Hash) and options.empty?
            options = path
          else
            raise ArgumentError, "must be called with a path and/or options"
          end

          if @scope[:scope_level] == :resources
            with_scope_level(:root) do
              scope(parent_resource.path) do
                super(options)
              end
            end
          else
            super(options)
          end
        end

        protected

          def parent_resource #:nodoc:
            @scope[:scope_level_resource]
          end

          def apply_common_behavior_for(method, resources, options, &block) #:nodoc:
            if resources.length > 1
              resources.each { |r| send(method, r, options, &block) }
              return true
            end

            if resource_scope?
              nested { send(method, resources.pop, options, &block) }
              return true
            end

            options.keys.each do |k|
              (options[:constraints] ||= {})[k] = options.delete(k) if options[k].is_a?(Regexp)
            end

            scope_options = options.slice!(*RESOURCE_OPTIONS)
            unless scope_options.empty?
              scope(scope_options) do
                send(method, resources.pop, options, &block)
              end
              return true
            end

            unless action_options?(options)
              options.merge!(scope_action_options) if scope_action_options?
            end

            false
          end

          def action_options?(options) #:nodoc:
            options[:only] || options[:except]
          end

          def scope_action_options? #:nodoc:
            @scope[:options] && (@scope[:options][:only] || @scope[:options][:except])
          end

          def scope_action_options #:nodoc:
            @scope[:options].slice(:only, :except)
          end

          def resource_scope? #:nodoc:
            RESOURCE_SCOPES.include? @scope[:scope_level]
          end

          def resource_method_scope? #:nodoc:
            RESOURCE_METHOD_SCOPES.include? @scope[:scope_level]
          end

          def with_exclusive_scope
            begin
              old_name_prefix, old_path = @scope[:as], @scope[:path]
              @scope[:as], @scope[:path] = nil, nil

              with_scope_level(:exclusive) do
                yield
              end
            ensure
              @scope[:as], @scope[:path] = old_name_prefix, old_path
            end
          end

          def with_scope_level(kind, resource = parent_resource)
            old, @scope[:scope_level] = @scope[:scope_level], kind
            old_resource, @scope[:scope_level_resource] = @scope[:scope_level_resource], resource
            yield
          ensure
            @scope[:scope_level] = old
            @scope[:scope_level_resource] = old_resource
          end

          def resource_scope(kind, resource) #:nodoc:
            with_scope_level(kind, resource) do
              scope(parent_resource.resource_scope) do
                yield
              end
            end
          end

          def nested_options #:nodoc:
            options = { :as => parent_resource.member_name }
            options[:constraints] = {
              parent_resource.nested_param => param_constraint
            } if param_constraint?

            options
          end

          def param_constraint? #:nodoc:
            @scope[:constraints] && @scope[:constraints][parent_resource.param].is_a?(Regexp)
          end

          def param_constraint #:nodoc:
            @scope[:constraints][parent_resource.param]
          end

          def canonical_action?(action, flag) #:nodoc:
            flag && resource_method_scope? && CANONICAL_ACTIONS.include?(action.to_s)
          end

          def shallow_scoping? #:nodoc:
            shallow? && @scope[:scope_level] == :member
          end

          def path_for_action(action, path) #:nodoc:
            prefix = shallow_scoping? ?
              "#{@scope[:shallow_path]}/#{parent_resource.shallow_scope}" : @scope[:path]

            if canonical_action?(action, path.blank?)
              prefix.to_s
            else
              "#{prefix}/#{action_path(action, path)}"
            end
          end

          def action_path(name, path = nil) #:nodoc:
            name = name.to_sym if name.is_a?(String)
            path || @scope[:path_names][name] || name.to_s
          end

          def prefix_name_for_action(as, action) #:nodoc:
            if as
              as.to_s
            elsif !canonical_action?(action, @scope[:scope_level])
              action.to_s
            end
          end

          def name_for_action(as, action) #:nodoc:
            prefix = prefix_name_for_action(as, action)
            prefix = Mapper.normalize_name(prefix) if prefix
            name_prefix = @scope[:as]

            if parent_resource
              return nil unless as || action

              collection_name = parent_resource.collection_name
              member_name = parent_resource.member_name
            end

            name = case @scope[:scope_level]
            when :nested
              [name_prefix, prefix]
            when :collection
              [prefix, name_prefix, collection_name]
            when :new
              [prefix, :new, name_prefix, member_name]
            when :member
              [prefix, shallow_scoping? ? @scope[:shallow_prefix] : name_prefix, member_name]
            when :root
              [name_prefix, collection_name, prefix]
            else
              [name_prefix, member_name, prefix]
            end

            if candidate = name.select(&:present?).join("_").presence
              # If a name was not explicitly given, we check if it is valid
              # and return nil in case it isn't. Otherwise, we pass the invalid name
              # forward so the underlying router engine treats it and raises an exception.
              if as.nil?
                candidate unless @set.routes.find { |r| r.name == candidate } || candidate !~ /\A[_a-z]/i
              else
                candidate
              end
            end
          end

          def set_member_mappings_for_resource
            member do
              get :edit if parent_resource.actions.include?(:edit)
              get :show if parent_resource.actions.include?(:show)
              if parent_resource.actions.include?(:update)
                patch :update
                put :update
              end
              delete :destroy if parent_resource.actions.include?(:destroy)
            end
          end
      end
      module Concerns
        def concern(name, callable = nil, &block)
          callable ||= lambda { |mapper, options| mapper.instance_exec(options, &block) }
          @concerns[name] = callable
        end
        def concerns(*args)
          options = args.extract_options!
          args.flatten.each do |name|
            if concern = @concerns[name]
              concern.call(self, options)
            else
              raise ArgumentError, "No concern named #{name} was found!"
            end
          end
        end
      end

      def initialize(set) #:nodoc:
        @set = set
        @scope = { :path_names => @set.resources_path_names }
        @concerns = {}
      end

      include Base
      include HttpHelpers
      include Scoping
      include Concerns
      include Resources
    end
  end
end
