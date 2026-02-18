# frozen_string_literal: true

module Funes
  # Provides a human-readable representation of your model instances through
  # the +inspect+ and +pretty_print+ methods.
  #
  # Ported from Rails PR #56521 (ActiveModel::Inspection). When that PR ships
  # in a future Rails release, this module can be removed with no API change.
  #
  # This module requires that the including class has an +@attributes+ instance
  # variable (as provided by ActiveModel::Attributes) and responds to
  # +attribute_names+.
  #
  # == Configuration
  #
  # The inspection output can be customized through two class attributes:
  #
  # * +filter_attributes+ - An array of attribute names whose values should be
  #   masked in the output. Useful for sensitive data like passwords.
  #
  # * +attributes_for_inspect+ - An array of attribute names to include in
  #   the output, or +:all+ to show all attributes (default).
  #
  # == Example
  #
  #   class Order::Placed < Funes::Event
  #     attribute :total, :decimal
  #     attribute :customer_id, :string
  #     attribute :password, :string
  #   end
  #
  #   event = Order::Placed.new(total: 99.99, customer_id: "cust-1", password: "secret")
  #   event.inspect
  #   # => "#<Order::Placed total: 99.99, customer_id: \"cust-1\", password: \"secret\">"
  #
  #   Order::Placed.filter_attributes = [:password]
  #   event.inspect
  #   # => "#<Order::Placed total: 99.99, customer_id: \"cust-1\", password: [FILTERED]>"
  #
  #   Order::Placed.attributes_for_inspect = [:total]
  #   event.inspect
  #   # => "#<Order::Placed total: 99.99>"
  #
  module Inspection
    extend ActiveSupport::Concern

    included do
      class_attribute :attributes_for_inspect, instance_accessor: false, default: :all
    end

    module ClassMethods
      # Returns an array of attribute names whose values should be masked in
      # the output of +inspect+.
      def filter_attributes
        if defined?(@filter_attributes)
          @filter_attributes
        elsif superclass.respond_to?(:filter_attributes)
          superclass.filter_attributes
        else
          []
        end
      end

      # Specifies attributes whose values should be masked in the output of
      # +inspect+.
      def filter_attributes=(attributes)
        @inspection_filter = nil
        @filter_attributes = attributes
      end

      def inspection_filter # :nodoc:
        if defined?(@filter_attributes) && @filter_attributes
          @inspection_filter ||= begin
            mask = InspectionMask.new(ActiveSupport::ParameterFilter::FILTERED)
            ActiveSupport::ParameterFilter.new(@filter_attributes, mask: mask)
          end
        elsif superclass.respond_to?(:inspection_filter)
          superclass.inspection_filter
        else
          @inspection_filter ||= begin
            mask = InspectionMask.new(ActiveSupport::ParameterFilter::FILTERED)
            ActiveSupport::ParameterFilter.new([], mask: mask)
          end
        end
      end
    end

    # Returns the attributes of the model as a nicely formatted string.
    def inspect
      inspect_with_attributes(attributes_for_inspect)
    end

    # Returns all attributes of the model as a nicely formatted string,
    # ignoring +.attributes_for_inspect+.
    def full_inspect
      inspect_with_attributes(all_attributes_for_inspect)
    end

    # Takes a PP and prettily prints this model to it, allowing you to get a
    # nice result from <tt>pp model</tt> when pp is required.
    def pretty_print(pp)
      return super if custom_inspect_method_defined?
      pp.object_address_group(self) do
        if @attributes
          attr_names = attributes_for_inspect.select { |name| @attributes.key?(name.to_s) }
          pp.seplist(attr_names, proc { pp.text "," }) do |attr_name|
            attr_name = attr_name.to_s
            pp.breakable " "
            pp.group(1) do
              pp.text attr_name
              pp.text ":"
              pp.breakable
              value = attribute_for_inspect(attr_name)
              pp.text value
            end
          end
        else
          pp.breakable " "
          pp.text "not initialized"
        end
      end
    end

    # Returns a formatted string for the given attribute, suitable for use in
    # +inspect+ output.
    #
    # Long strings are truncated, dates and times are formatted with
    # +to_fs(:inspect)+, and filtered attributes show +[FILTERED]+.
    def attribute_for_inspect(attr_name)
      attr_name = attr_name.to_s
      value = @attributes.fetch_value(attr_name)
      format_for_inspect(attr_name, value)
    end

    private
      class InspectionMask < DelegateClass(::String)
        def pretty_print(pp)
          pp.text __getobj__
        end
      end
      private_constant :InspectionMask

      def inspection_filter
        self.class.inspection_filter
      end

      def inspect_with_attributes(attributes_to_list)
        inspection = if @attributes
          attributes_to_list.filter_map do |name|
            name = name.to_s
            if @attributes.key?(name)
              "#{name}: #{attribute_for_inspect(name)}"
            end
          end.join(", ")
        else
          "not initialized"
        end

        "#<#{self.class} #{inspection}>"
      end

      def attributes_for_inspect
        self.class.attributes_for_inspect == :all ? all_attributes_for_inspect : self.class.attributes_for_inspect
      end

      def all_attributes_for_inspect
        return [] unless @attributes
        attribute_names
      end

      def format_for_inspect(name, value)
        if value.nil?
          value.inspect
        else
          inspected_value = if value.is_a?(String) && value.length > 50
            "#{value[0, 50]}...".inspect
          elsif value.is_a?(BigDecimal)
            value.to_s("F")
          elsif value.is_a?(Date) || value.is_a?(Time)
            if value.respond_to?(:to_fs)
              %("#{value.to_fs(:inspect)}")
            else
              %("#{value}")
            end
          else
            value.inspect
          end

          inspection_filter.filter_param(name, inspected_value)
        end
      end

      def custom_inspect_method_defined?
        self.class.instance_method(:inspect).owner != Funes::Inspection
      end
  end
end
