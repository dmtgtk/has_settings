module HasSettings
  @@config = {
    :settings_class_name => 'Setting',
    :settings_attribute_name => :settings,
    :global_settings_attribute_name => :global
  }

  mattr_reader :config
end
