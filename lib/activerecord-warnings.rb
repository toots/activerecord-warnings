require 'active_record'
require 'active_record/base'
require 'active_record/validations'

module ActiveRecord #:nodoc:
  module Warnings 
    module InstanceMethods
      # The warnings that are set on this record, equivalent to normal ActiveRecord errors but does not prevent
      # the record from saving.
      def warnings
        @warnings ||= ActiveModel::Errors.new(self)
      end

      # Does this record have warnings?
      def warnings?(context = nil)
        valid_with_warnings?(context)
        not @warnings.empty?
      end

      # Wrapper for valid? to also clear warnings.
      def valid_with_warnings?(context = nil)
        warnings.clear
        valid_without_warnings?(context = nil)
      end
    end

    def self.extended(base) #:nodoc:
      base.class_eval do
        include InstanceMethods
      end
      base.singleton_class.class_eval do
        alias_method(:validate_for_errors, :validate)
      end
       
      base.send(:alias_method, :valid_without_warnings?, :valid?)
      base.send(:alias_method, :valid?,                  :valid_with_warnings?)
    end

    # Wraps instances of ActiveRecord::Base so that the `errors` method actually uses the warnings.
    class WarningProxy < ActiveSupport::BasicObject #:nodoc:
      def initialize(owner)
        @owner = owner
      end

      def errors
        @owner.warnings
      end

      def respond_to?(name, include_private = false)
        super or @owner.respond_to?(name, include_private)
      end

      def method_missing(*args, &block)
        @owner.send(*args, &block)
      end
    end

    # Describes a set of standard ActiveRecord validations that should not prevent the instance from being
    # saved but could cause warnings that need to be presented to the user.
    def warnings(&block)
      switch_validations(:warnings)
      instance_eval(&block)
    ensure
      switch_validations(:errors)
    end

    def switch_validations(context) #:nodoc:
      singleton_class.class_eval do
        alias_method(:validate, :"validate_for_#{context}")
      end
    end
    private :switch_validations

    def validate_for_warnings(*args, &block)
      options = args.extract_options!
      args = args.map do |klass|
        klass = klass.clone
        klass.class_eval do
          alias_method(:validate_proxy, :validate)
          def validate(record)
            validate_proxy(WarningProxy.new(record))
          end
        end
        klass
      end
      args << options

      if block_given?
        validate_for_errors(*args) do
          WarningProxy.new(self).instance_eval(&block)
        end
      else
        validate_for_errors(*args)
      end
    end
  end
end

class ActiveRecord::Base #:nodoc:
  extend ActiveRecord::Warnings
end
