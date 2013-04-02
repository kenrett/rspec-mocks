module RSpec
  module Mocks
    # @private
    class MethodDouble < Hash
      # @private
      attr_reader :method_name, :object, :original_method

      # @private
      def initialize(object, method_name, proxy)
        @method_name = method_name
        @object = object
        @proxy = proxy

        @method_stasher = InstanceMethodStasher.new(object_singleton_class, @method_name)
        @method_is_proxied = false
        @original_method = find_original_method
        store(:expectations, [])
        store(:stubs, [])
      end

      def find_original_method
        method_handle_name = if any_instance_class_recorder_observing_method?(@object.class)
          @object.class.__recorder.build_alias_method_name(@method_name)
        else
          @method_name
        end

        ::RSpec::Mocks.method_handle_for(@object, method_handle_name)
      rescue NameError
        Proc.new do |*args, &block|
          @object.__send__(:method_missing, @method_name, *args, &block)
        end
      end

      # @private
      def expectations
        self[:expectations]
      end

      # @private
      def stubs
        self[:stubs]
      end

      # @private
      def visibility
        if TestDouble === @object
          'public'
        elsif object_singleton_class.private_method_defined?(@method_name)
          'private'
        elsif object_singleton_class.protected_method_defined?(@method_name)
          'protected'
        else
          'public'
        end
      end

      def any_instance_class_recorder_observing_method?(klass)
        return true if klass.__recorder.already_observing?(@method_name)
        superklass = klass.superclass
        return false if superklass.nil?
        any_instance_class_recorder_observing_method?(superklass)
      end

      # @private
      def object_singleton_class
        class << @object; self; end
      end

      # @private
      def configure_method
        warn_if_nil_class
        @original_visibility = visibility_for_method
        @method_stasher.stash unless @method_is_proxied
        define_proxy_method
      end

      # @private
      def define_proxy_method
        return if @method_is_proxied

        object_singleton_class.class_eval <<-EOF, __FILE__, __LINE__ + 1
          def #{@method_name}(*args, &block)
            ::RSpec::Mocks.proxy_for(self).message_received :#{@method_name}, *args, &block
          end
          #{visibility_for_method}
        EOF
        @method_is_proxied = true
      end

      # @private
      def visibility_for_method
        "#{visibility} :#{method_name}"
      end

      # @private
      def restore_original_method
        return unless @method_is_proxied

        object_singleton_class.__send__(:remove_method, @method_name)
        @method_stasher.restore
        restore_original_visibility

        @method_is_proxied = false
      end

      # @private
      def restore_original_visibility
        return unless object_singleton_class.method_defined?(@method_name) || object_singleton_class.private_method_defined?(@method_name)
        object_singleton_class.class_eval(@original_visibility, __FILE__, __LINE__)
      end

      # @private
      def verify
        expectations.each {|e| e.verify_messages_received}
      end

      # @private
      def reset
        reset_nil_expectations_warning
        restore_original_method
        clear
      end

      # @private
      def clear
        expectations.clear
        stubs.clear
      end

      # @private
      def add_expectation(error_generator, expectation_ordering, expected_from, opts, &implementation)
        configure_method
        expectation = MessageExpectation.new(error_generator, expectation_ordering,
                                             expected_from, self, 1, opts, &implementation)
        expectations << expectation
        expectation
      end

      # @private
      def add_negative_expectation(error_generator, expectation_ordering, expected_from, &implementation)
        configure_method
        expectation = NegativeMessageExpectation.new(error_generator, expectation_ordering,
                                                     expected_from, self, &implementation)
        expectations.unshift expectation
        expectation
      end

      # @private
      def build_expectation(error_generator, expectation_ordering)
        expected_from = IGNORED_BACKTRACE_LINE
        MessageExpectation.new(error_generator, expectation_ordering, expected_from, self)
      end

      # @private
      def add_stub(error_generator, expectation_ordering, expected_from, opts={}, &implementation)
        configure_method
        stub = MessageExpectation.new(error_generator, expectation_ordering, expected_from,
                                      self, :any, opts, &implementation)
        stubs.unshift stub
        stub
      end

      # @private
      def add_default_stub(*args, &implementation)
        return if stubs.any?
        add_stub(*args, &implementation)
      end

      # @private
      def remove_stub
        raise_method_not_stubbed_error if stubs.empty?
        expectations.empty? ? reset : stubs.clear
      end

      # @private
      def proxy_for_nil_class?
        NilClass === @object
      end

      # @private
      def warn_if_nil_class
        if proxy_for_nil_class? & RSpec::Mocks::Proxy.warn_about_expectations_on_nil
          Kernel.warn("An expectation of :#{@method_name} was set on nil. Called from #{caller[4]}. Use allow_message_expectations_on_nil to disable warnings.")
        end
      end

      # @private
      def raise_method_not_stubbed_error
        raise MockExpectationError, "The method `#{method_name}` was not stubbed or was already unstubbed"
      end

      # @private
      def reset_nil_expectations_warning
        RSpec::Mocks::Proxy.warn_about_expectations_on_nil = true if proxy_for_nil_class?
      end

      # @private
      IGNORED_BACKTRACE_LINE = 'this backtrace line is ignored'
    end
  end
end
