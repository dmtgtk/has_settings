require File.join(File.dirname(__FILE__), 'config')

module HasSettings  #:nodoc:
  module ActiveRecordExtensions  #:nodoc:
    def self.included(base)  #:nodoc:
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      ##
      #
      #
      def acts_as_setting(*args)
        options = args.extract_options!
        attribute_name = args.shift || HasSettings.config[:global_settings_attribute_name]
        association_name = "_#{attribute_name}"
        
        named_scope association_name.to_sym,
          :conditions => 'configurable_id IS NULL AND configurable_type IS NULL'

        (class << self; self; end).instance_eval do
          define_method attribute_name do
            instance_variable_get(:"@#{attribute_name.to_s}") || instance_variable_set(:"@#{attribute_name.to_s}", SettingsAccessor.new(self, association_name.to_sym, nil))
          end
        end

        belongs_to :configurable,
          :polymorphic => true
        
        include HasSettings::ActiveRecordExtensions::InstanceMethods
      end

      ##
      #
      #
      def has_settings(*args)
        options = args.extract_options!
        attribute_name = args.shift || HasSettings.config[:settings_attribute_name]
        association_name = "_#{attribute_name}"
        class_name = options[:class_name] || HasSettings.config[:settings_class_name]
        
        has_many association_name.to_sym,
          :class_name => class_name,
          :as => :configurable,
          :dependent => :destroy
        
        define_method attribute_name do
          instance_variable_get(:"@#{attribute_name.to_s}") || instance_variable_set(:"@#{attribute_name.to_s}", SettingsAccessor.new(self, association_name.to_sym, options[:inherit]))
        end
      end
    end
    
    ##
    # 
    #
    class SettingsAccessor
      
      # Start with a blank slate
      instance_methods.each { |m| undef_method m unless m.to_s =~ /(^__|inspect)/}
      
      ##
      # Initialize new accessor proxy
      #
      # +owner+ - owner of the setting accessor proxy
      # +association+ - setting assoc attribute name in the owner's class
      # +heritage+ - inherited settings proxy, can be either a class of top-level setting model, symbol or array.
      #
      def initialize(owner, association, heritage)
        @owner = owner
        @association = @owner.send(association)
        if heritage.is_a? Array
          @parent_object = heritage.first
          @parent_accessor = heritage.second
        else
          @parent_object = heritage
        end
        if @parent_object && @parent_accessor.nil?
          if @parent_object.is_a? Class
            @parent_accessor = HasSettings.config[:global_settings_attribute_name]
          else
            @parent_accessor = HasSettings.config[:settings_attribute_name]
          end
        end
      end
      
      ##
      # Test if setting +symbol_or_name+ has value. If +include_inherited+ is set to false, only settings defined
      # for the receiver will be checked, inheritance is ignored.
      #
      def has_setting?(symbol_or_name, include_inherited = true)
        found = find_setting(symbol_or_name.to_s) != nil
        if found
          return found
        elsif include_inherited && has_parent?
          return parent.__send__(:has_setting?, symbol_or_name)
        end
        false
      end
      
      ##
      # Returns all defined setting as a Hash. If +include_inherited+ is set to false, only settings defined
      # for the receiver will be returned, inheritance is ignored.
      #
      def all(include_inherited = true)
        hash = {}
        @association.all.each { |setting| hash[setting.name.to_sym] = setting.value }
        if include_inherited
          proxy = parent
          while proxy
            proxy_hash = proxy.__send__(:all, false)
            hash.reverse_merge! proxy_hash
            proxy = proxy.__send__(:parent)
          end
        end
        hash
      end

      private
      
      def method_missing(symbol, *args)
        name = symbol.to_s
        if name =~ /=$/
          put_setting(name.gsub(/=$/, ''), args.first)
        else
          get_setting(name)
        end
      end
      
      def put_setting(name, value)
        setting = find_setting(name)
        if value.nil?
          setting.delete if setting
        else
          if setting.nil?
            if @owner.respond_to?(:new_record?) && @owner.new_record?
              setting = @association.build(:name => name, :value => value)
            else
              setting = @association.create(:name => name, :value => value)
            end
          else
            setting.update_attributes(:value => value)
          end
        end
      end
      
      def get_setting(name)
        setting = find_setting(name).try(:value)
        if setting.nil? && has_parent?
          return parent.__send__(:get_setting, name)
        else
          return setting
        end
      end

      def find_setting(name)
        @association.first(:conditions => ['name = ?', name])
      end

      def has_parent?
        !! @parent_object
      end
      
      def parent
        if has_parent?
          parent = @parent_object.is_a?(Class) ? @parent_object : @owner.__send__(@parent_object)
          parent.__send__(@parent_accessor)
        else
          nil
        end
      end
    end
    
    module InstanceMethods
      def value
        case self.value_type
        when nil
          nil
        when 'TrueClass'
          true
        when 'FalseClass'
          false
        when 'String'
          self[:value]
        when 'Float'
          Float(self[:value])
        when 'Fixnum', 'Bignum'
          Integer(self[:value])
        when 'Time'
          Time.parse(self[:value])
        when 'Date'
          Date.parse(self[:value])
        when 'DateTime'
          DateTime.parse(self[:value])
        when 'ActiveSupport::TimeWithZone'
          Time.zone.parse(self[:value])
        else
          raise "Unsupported value class"
        end
      end
      
      def value=(new_value)
        if new_value.nil?
          self[:value] = self.value_type = nil
        else
          new_type = new_value.class.to_s
          case new_type
          when 'String'
            self[:value] = new_value
            self.value_type = new_type
          when 'Float', 'Fixnum', 'Bignum', 'TrueClass', 'FalseClass'
            self[:value] = new_value.to_s
            self.value_type = new_type
          when 'Time', 'Date', 'DateTime', 'ActiveSupport::TimeWithZone'
            self[:value] = new_value.to_s(:rfc822)
            self.value_type = new_type
          else
            raise "Unsupported value class"
          end
        end
      end
    end
  
  end
end