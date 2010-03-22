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

module Pluginable
  extend self

  def self.receiver
    @receiver ||= nil
  end

  def self.redefinable
    @redefinable ||= {}
  end

  def self.plugins
    @plugins ||= []
  end

  def self.extended base
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

  def activate plugin_name
    # be careful about self here, need to explicit Pluginable
    
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
      #puts e.class_eval("class << self; self; end").ancestors.inspect
      e.extend ::Pluginable::PluginInit
      puts
      Pluginable.redefinable[e] << Pluginable.receiver.const_get("Plugin").const_get(plugin_name) if Pluginable.redefinable.has_key? e
    end
    plugin.unpack if plugin.respond_to?(:unpack)
    puts Pluginable.redefinable.inspect
  end

  module PluginInit
    def self.extended base
      puts "PluginInit extended by #{base}"
      puts base.class_eval("class << self; self; end").ancestors.inspect
      #puts base.new.instance_eval("class << self; self; end").ancestors.inspect
    end

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
        puts "Unpacking #{self}"
        puts
      end

      module Speaker
        #def self.included(receiver)
          #puts "including #{self.inspect} into #{receiver}"
          #receiver.send :include, InstanceMethods
          #unless receiver.respond_to?(:old_say)
            #puts "aliasing"
            #receiver.instance_eval do
              #alias :old_say :say
            #end
          #end
        #end

        #module InstanceMethods
          def say(what)
            super what.reverse
          end
        #end
      end
    end
  end
end

module Base
  
  VERSION = 0.1

  class Speaker
    def initialize
      puts instance_eval("class << self; self; end").ancestors.inspect
      puts
      #send :extend, Base::Plugins::Backward::SpeakerRedef

      # - quand un plugin est chargé, Base::Plugin.activate se charge de :
      #   - relever l'ensemble des modules définis par le plugin, avec un helper du genre :
      #     Foo.constants.map { |s| Foo.const_get s }.grep(Class) # à affiner bien sûr
      #   - étant donnée la liste des classes qui sont déclarées comme étant modifiables par les plugins :
      #     - si le plugin tente de modifier une classe de Base qui n'est pas dans la liste autorisée, erreur et ne pas charger le plugin
      #     - pour chacune des classes autorisée et modifiée par le plugin (module défini), ajouter une entrée dans plugins_hook
      # pour le reste, pareil :
      # - les classes modifiables extend un module qui redéfinit new, de façon à :
      #   - appeler self.extend [les plugins associés à self] (self étant une instance d'une classe modifiable, dans ce contexte)
      #   - appeler super
      # - le extend est réalisé pour chaque plugin présent dans plugins_hooks[NomDeLaClasseDeLInstance]
      #
      # À terme, ce qui serait cool, c'est d'en faire un gem, assez souple. Par défaut, toutes les classes et modules, récursivement,
      # d'un module ou d'une classe mère seraient modifiables (clés dans plugin_hooks), mais on pourrait faire un truc du genre :
      # Pluginable.config do
      #   only [Base::Server, Base::Config, Base::Speaker::Public]
      #   # ou bien :
      #   except [...]
      #   # toute autre conf. utile
      # end
      #
      # On aurait alors un DSL similaire à mon cas oneshot :
      # - activate "plugin" pour activer un plugin et le relier à toutes les classes concernées
      # - shutdown "plugin" ?
      # et la même architecture des fichiers/dossiers.
      puts instance_eval("class << self; self; end").ancestors.inspect
      puts
    end

    def say(what)
      p "say: #{what}"
    end
  end

  module Template
    class Templator
    end
  end

  class Server
    Base.extend Pluginable
    #puts Base.class_eval("class << self; self; end").ancestors.inspect
    #puts Base::Server.class_eval("class << self; self; end").ancestors.inspect

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
  end

end

#puts Base.fetch_nested(recursive: true)

#puts "---"

#Base.fetch_nested(recursive: true) { |e| puts "#{e} (#{e.class})"; e.new if e.is_a? Class }

#Base::Server.new

Base::Server.new

