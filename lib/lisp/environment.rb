module Lisp
  # The names visible at a point in the program, chained up to the base environment.
  class Environment
    def initialize(parent = nil)
      @parent = parent
      @names = {}
    end

    def define(name, value)
      @names[name] = value
    end

    def search(name)
      environment = self
      while environment
        return environment.own(name) if environment.has?(name)
        environment = environment.parent
      end
      raise Error, I18n.t("lisp.errors.unknown_name", name: name)
    end

    def freeze!
      @names.freeze
      self
    end

    protected

    attr_reader :parent

    def has?(name) = @names.key?(name)
    def own(name) = @names[name]
  end
end
