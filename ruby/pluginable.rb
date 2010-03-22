class Object
  # Look out for any class and/or module defined within the receiver.
  # The receiver must be a class or a module.
  #
  # call-seq:
  #   MyModule.fetch_nested                        => returns a flat array of every first-level nested classes and modules
  #   MyModule.fetch_nested(:only => :classes)     => returns a flat array of every first-level nested classes
  #   MyModule.fetch_nested(:only => :modules)     => returns a flat array of every first-level nested modules
  #   MyModule.fetch_nested(:recursive => true)    => performs a recursive search through descendants, returns one flat array
  #   MyModule.fetch_nested([options]) { |e| ... } => yield elements
  #
  # The matching elements are returned or yielded as Class or Module, so
  # one can use them directly to instanciate, mixin...
  #
  # Beware that when using the block form, the same element may be yielded
  # several times, depending on inclusions and requirements redundancy.
  # The flat array contains uniq entries.
  def fetch_nested(*args)
    options = {:recursive => false, :only => false}.merge! Hash[*args]
    #unless (options.reject { |k, v| [:recursive, :only].include? k }).empty?
      #raise ArgumentError, "Unexpected argument(s) (should be :recursive and/or :only)"
    #end

    # TODO: option :format => :array|:hash to return either a flat array (default) or a folded hash
    
    consts = []
    if self.class == "Module" || "Class"
      consts = case options[:only]
        when :classes
          self.constants.map { |c| self.const_get c }.grep(Class)
        when :modules
          tmp = self.constants.map { |c| self.const_get c }
          tmp.grep(Module) - tmp.grep(Class)
        when false
          self.constants.map { |c| self.const_get c }.grep(Module)
      end

      if consts.empty?
        return nil
      else
        if options[:recursive]
          consts.each do |c|
            if block_given?
              c.fetch_nested(recursive: true, only: options[:only]) { |nested| yield nested }
            else
              nested = c.fetch_nested(recursive: true, only: options[:only])
              (consts << nested).flatten! unless nested.nil?
            end
          end
        end
        if block_given?
          consts.uniq.each { |c| yield c }
        else
          return consts.uniq
        end
      end
    else
      # neither a class or a module
      return nil
    end
  end
end

# This module adds pluginable behavior to some module or class.
# It means the module or class will be able to activate plugins
# which have been written on the purpose of adding new or redefining
# existing behaviors (methods).
#
# Plugins can alter class or instance methods, within modules or classes.
# A convention in plugins definitions makes it possible to auto-discover
# which modules or classes of the receiver are concerned by the plugin
# to be activated. Those modules or classes will gain some new behavior
# if the plugin declares so, while retaining the ability to fallback on
# their original behavior via simple inheritance. Pluginable will also
# automagically hook class and instance methods in their proper location
# if a simple structure convention is followed in the plugin definition.
#
# TODO
# The hooking process can be configured (no more automagical hooking)
# using the unpack method each plugin may provide:
#   def unpack
#     # ... design pending
#   end
#
# If several plugins are activated and performs some redefinitions
# in a class or module of the receiver, one has to pay extra attention
# to chained behavior and inconsistency. It's good practice to always
# call super at some point so as to traverse the all plugins inheritance
# chain until the original definition is reached.
#
# If you want to completely overwrite the original behavior while being
# able to activate multiple plugins, a nice way to go is to write a
# SuperPlugin which redefines the method you're targeting at, without
# calling super. Activate this SuperPlugin first, then activate the other
# plugins, using super in their redefinitions so as to reach the SuperPlugin
# implementation in the end.
#
# TODO
# If you want to bold-skip a plugin once, you may first check wether
# it's activated using MyProject.plugins. If so, you may then call
# <code>MyProject.bypass :plugin_name</code>, which will perform
# <code>shutdown</code> and <code>activate</code> in sequence while
# retaining the inheritance position of the bypassed plugin.
module Pluginable
  extend self

  # FIXME
  # en fait, à part activate, je dois pouvoir tout passer en private, non ?

  # FIXME
  # le transformer en attr_reader peut-être ?
  # The base module or class which called extend Pluginable
  def self.receiver
    @receiver ||= nil
  end

  # This hash holds the plugins hooks. Its structure is like this:
  # a module or class within the receiver => array of plugins performing redef on it
  def self.redefinable
    @redefinable ||= {}
  end

  # A list of all active plugins for the receiver.
  def self.plugins
    @plugins ||= []
  end

  def self.extended base #:nodoc:
    puts "Initializing Pluginable..."
    @receiver = base
    puts @receiver

    # TODO
    # peut-être à terme à bouger dans une méthode self.init
    # de façon à pouvoir découpler le extend de l'initialization,
    # ce qui permettrait entre temps de configurer un peu son
    # Pluginable (options :only, :except, etc.)
    # Ou sinon, garder ça ici et mettre la conf dans un fichier tiers,
    # à lire juste avant le fetch_nested de façon à pouvoir affiner la
    # clause unless
    base.fetch_nested(recursive: true) do |e|
      redefinable[e] ||= [] unless e.name =~ /#{@receiver}::Plugin/
    end
    puts "> redefinable: #{redefinable.inspect}"
    puts "Plugins init done."
    puts
  end

  # Activate a plugin.
  #
  # Must be called by the receiver, ie. the module or class which called
  # <code>extend Pluginable</code>.
  #
  #   module MyProject
  #     extend Pluginable
  #
  #     class Foo
  #       # ...
  #     end
  #
  #     class Server
  #       def initialize
  #         MyProject.activate :some_super_plugin_I_wrote
  #         MyProject.activate "anotherPlugin"
  #       end
  #     end
  #   end
  #
  def activate plugin_name
    # be careful about self here, need to explicit Pluginable

    # TODO: gérer en arguments les chaines et les symboles,
    # camelcased on underscored (faire un helper private)
    
    plugin_name = plugin_name.capitalize

    begin
      plugin = Pluginable.receiver.const_get("Plugin").const_get(plugin_name)
    rescue
      raise "No such plugin \"#{plugin_name}\""
    end

    Pluginable.plugins << plugin_name
    plugin.fetch_nested(recursive: true, only: :modules) do |e|
      e = e.name.split("::").last
      e = Pluginable.receiver.const_get e

      puts
      e.extend ::Pluginable::PluginInit
      puts
      Pluginable.redefinable[e] << Pluginable.receiver.const_get("Plugin").const_get(plugin_name) if Pluginable.redefinable.has_key? e
    end
    plugin.unpack if plugin.respond_to?(:unpack)
    puts Pluginable.redefinable.inspect
  end

  # TODO
  # def shutdown
  # end

  # TODO
  # def bypass
  # end

  # This module is responsible for extending class instances with
  # new behavior defined by some plugin(s). It's the responsability
  # of the plugins to call super or not so as to fallback on the
  # original behavior: this module only has the hooks up and running.
  module PluginInit
    def self.extended base
      puts "PluginInit extended by #{base}"
      puts base.class_eval("class << self; self; end").ancestors.inspect
    end

    # Redefine initialize/new so as to call extend on new instances.
    def new *args, &block
      puts "--------- Initializing through PluginInit for #{self}"
      o = super
      puts "super: #{o}"
      puts "self: #{self}"
      puts Pluginable.redefinable
      puts Pluginable.redefinable[self].first.class
      puts "---------"
      puts o.instance_eval("class << self; self; end").ancestors.inspect
      Pluginable.redefinable[self].reverse.each do |plugin_module|
        o.extend(plugin_module.const_get(self.name.split("::").last)) 
      end unless Pluginable.redefinable[self].empty?
      puts o.instance_eval("class << self; self; end").ancestors.inspect
      o
    end
  end
end

module Base
  module Plugin
    module Backward
      def self.unpack
        # ne sert à rien dans cet exemple, mais pourrait être utile
        # dans certains cas (send :include, ClassMethods par exemple)
        puts "Unpacking #{self}"
        puts
      end

      # TODO
      # peut-être imposer la convention que les classes de Base redéfinies ici
      # sont à placer dans un module du même nom (Base, donc) ?
      # Auquel cas, modifier en conséquence le hooking automatique dans Pluginable#activate etc.
      # module Base
      module Speaker
        def say what
          super what.reverse
        end
      end
      #end

      # TODO
      # Voilà la convention que je propose :
      # module Base::Plugin::Backward...
      # module Base
      #   module Speaker
      #     def self.unpack
      #       # this is configuration over convention
      #     end
      #
      #     # this is convention
      #     module InstanceMethods
      #       def say what
      #         super what.reverse
      #       end
      #     end
      #
      #     module ClassMethods
      #       def foobar
      #       end
      #     end
      #   end
      # end
      #
      # Dans Pluginable.activate, on vérifie s'il existe la méthode unpack :
      # - si oui, alors l'exécuter et c'est tout ;
      # - si non, alors obtenir la liste des modules déclarés par le plugin, puis pour chacun de
      #   ceux qui sont dans @redefinable :
      #   - faire un extend ClassMethods sur le module ou la classe correspondante du receiver ;
      #   - faire un extend Pluginable::PlugInit sur le module ou la classe correspondante du receiver,
      #     de façon à faire le extend InstanceMethods sur les instances, le moment venu.
      #
      # De cette façon, on n'a rien à déclarer du tout, c'est automagical à partir du moment où
      # on suit la convention (et on peut s'en passer si on veut, avec unpack, peut-être à renommer
      # custom_unpack du coup).
    end
  end
end

module Base

  VERSION = 0.1

  class Speaker
    def initialize
      puts "A new speaker has been requested."
      puts "ancestors: " + instance_eval("class << self; self; end").ancestors.inspect
      puts
    end

    def say something
      p "say: #{something}"
    end
  end

  module Template
    class Templator
    end
  end

  class Server
    Base.extend Pluginable

    s = Base::Speaker.new
    s.say 'hello world'
    puts

    Base.activate 'backward'

    s.say 'hello world'

    puts
   
    puts "-@-@-@-@-@-@-@-"
    s2 = Base::Speaker.new
    puts "-@-@-@-@-@-@-@-"
    s2.say 'hello world'

    #TODO
    #Base.shutdown :backward
    # ie. la méthode shutdown pour virer le plugin (mais ça voudrait dire unextend
    # et ça je sais pas si c'est possible ! Auquel cas il faudrait gruiker, genre
    # undef les méthodes du module plugin, puis possiblité de les redef… Peut-être
    # utiliser la technique des BlankObject avec hide et reveal ?)
    #
    # et la possiblitié de passer soit une chaîne, soit un symbole comme argument
    # de activate et shutdown
    # plus insensibilité à la casse, peut-être
  end

end

Base::Server.new

# TODO
# specs!

