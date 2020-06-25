# frozen_string_literal: true

require 'ruby2_keywords'

require_relative 'memery/version'

## Module for memoization
module Memery
  class << self
    def monotonic_clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def method_visibility(klass, method_name)
      if klass.private_method_defined?(method_name)
        :private
      elsif klass.protected_method_defined?(method_name)
        :protected
      elsif klass.public_method_defined?(method_name)
        :public
      else
        raise ArgumentError, "Method #{method_name} is not defined on #{klass}"
      end
    end
  end

  OUR_BLOCK = lambda do
    extend(ClassMethods)
    include(InstanceMethods)
    extend ModuleMethods if instance_of?(Module)
  end

  private_constant :OUR_BLOCK

  ## Moudle for module methods,
  ## when the root module is included into some module
  module ModuleMethods
    def included(base = nil, &block)
      if base.nil? && block
        super do
          instance_exec(&block)
          instance_exec(&OUR_BLOCK)
        end
      else
        base.instance_exec(&OUR_BLOCK)
      end
    end
  end

  extend ModuleMethods

  ## Module for class methods
  module ClassMethods
    def memoized_methods
      @memoized_methods ||= {}
    end

    def memoize(method_name, condition: nil, ttl: nil)
      original_visibility = Memery.method_visibility(self, method_name)

      original_method = memoized_methods[method_name] = instance_method(method_name)

      undef_method method_name

      define_method method_name do |*args, &block|
        if block || (condition && !instance_exec(&condition))
          return original_method.bind(self).call(*args, &block)
        end

        method_key = "#{method_name}_#{original_method.object_id}"

        store = (@_memery_memoized_values ||= {})[method_key] ||= {}

        if store.key?(args) && (ttl.nil? || Memery.monotonic_clock <= store[args][:time] + ttl)
          return store[args][:result]
        end

        result = original_method.bind(self).call(*args)
        @_memery_memoized_values[method_key][args] =
          { result: result, time: Memery.monotonic_clock }
        result
      end

      ruby2_keywords method_name

      send original_visibility, method_name

      method_name
    end

    def memoized?(method_name)
      memoized_methods.key?(method_name)
    end
  end

  ## Module for instance methods
  module InstanceMethods
    def clear_memery_cache!
      @_memery_memoized_values = {}
    end
  end
end
