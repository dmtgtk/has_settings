require 'test/unit'

require 'rubygems'
require 'active_record'

$:.unshift File.dirname(__FILE__) + '/../lib'
require File.dirname(__FILE__) + '/../init'

ActiveRecord::Base.logger = Logger.new('test.log')
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

class Setting < ActiveRecord::Base  #:nodoc:
  acts_as_setting
end

class Group < ActiveRecord::Base  #:nodoc:
  has_many :users
  has_settings                   :inherit => Setting
  has_settings :custom_settings, :inherit => [Setting, :global]
end

class User < ActiveRecord::Base  #:nodoc:
  belongs_to :group
  has_settings :private_settings
  has_settings                         :inherit => :group
  has_settings :without_group,         :inherit => Setting
  has_settings :group_custom_settings, :inherit => [:group, :custom_settings]
end

class SettingTest < Test::Unit::TestCase  #:nodoc:

  def setup
    ActiveRecord::Schema.suppress_messages do
      ActiveRecord::Schema.define(:version => 1) do
        create_table :settings do |t|
          t.integer :configurable_id
          t.string  :configurable_type
          t.string  :name, :limit => 40, :null => false
          t.string  :value
          t.string  :value_type
        end
      
        create_table :groups do |t|
          t.timestamps
        end
      
        create_table :users do |t|
          t.references  :group
          t.timestamps
        end
      end
    end
  end

  def teardown
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.drop_table(table)
    end
  end
  
  def test_string_setting_value
    s = Setting.new
    s.value = 'blah'
    assert_equal('blah', s.value)
    s.value = 'bleh'
    assert_equal('bleh', s.value)
  end
  
  def test_fixnum_setting_value
    s = Setting.new
    s.value = 42
    assert_equal(42, s.value)
    s.value = -100
    assert_equal(-100, s.value)
  end
  
  def test_bignum_setting_value
    s = Setting.new
    s.value = 424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242
    assert_equal(424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242, s.value)
    s.value = -912472384682374682376487263487687
    assert_equal(-912472384682374682376487263487687, s.value)
  end
  
  def test_float_setting_value
    s = Setting.new
    s.value = 42.42
    assert_equal(42.42, s.value)
    s.value = -1e12
    assert_equal(-1e12, s.value)
  end
  
  def test_date_setting_value
    s = Setting.new
    s.value = Date.today
    assert_equal('Date', s.value_type)
    assert_equal(Date.today, s.value)
    s.value = Date.today + 10
    assert_equal(Date.today + 10, s.value)
  end
  
  def test_datetime_setting_value
    s = Setting.new
    dt1 = DateTime.now
    s.value = dt1
    assert_equal('DateTime', s.value_type)
    assert_equal(dt1.to_s, s.value.to_s)
    dt2 = 7.days.ago
    s.value = dt2
    assert_equal(dt2.to_s, s.value.to_s)
  end
  
  def test_time_setting_value
    s = Setting.new
    t1 = Time.now
    s.value = t1
    assert_equal('Time', s.value_type)
    assert_equal(t1.to_s, s.value.to_s)
    t2 = Time.now + 42
    s.value = t2
    assert_equal(t2.to_s, s.value.to_s)
  end
  
  def test_time_with_zone_setting_value
    s = Setting.new
    Time.zone = 'International Date Line West'
    t1 = Time.zone.now
    s.value = t1
    assert_equal('ActiveSupport::TimeWithZone', s.value_type)
    assert_equal(t1.to_s, s.value.to_s)
    t2 = t1 + 42
    s.value = t2
    assert_equal(t2.to_s, s.value.to_s)
  end
  
  def test_global_settings
    assert(Setting.global.all.empty?)
    Setting.global.s1 = 'blah'
    Setting.global.s2 = 5
    assert_equal(2, Setting.global.all.size)
  end
  
  def test_global_settings_get_and_set
    Setting.global.s1 = 'bleh'
    Setting.global.s2 = 42
    g = Setting.global.all
    assert_equal(g.size, 2)
    assert(g.has_key? :s1)
    assert_equal(String, g[:s1].class)
    assert_equal('bleh', g[:s1])
    assert(g.has_key? :s2)
    assert_equal(Fixnum, g[:s2].class)
    assert_equal(42, g[:s2])
  end
  
  def test_global_settings_delete
    Setting.global.s = 'bloh'
    assert(Setting.global.all.has_key? :s)
    assert_equal(String, Setting.global.all[:s].class)
    assert_equal('bloh', Setting.global.all[:s])
    Setting.global.s = nil
    assert_equal(0, Setting.global.all.size)
  end
  
  def test_group_settings
    group = Group.create
    
    assert(group.settings.all.empty?)
    group.settings.s1 = 'foo'
    group.settings.s2 = true
    group.settings.s3 = false
    assert_equal(3, group.settings.all.size)
    assert_equal(true, group.custom_settings.has_setting?(:s1))
    assert_equal('foo', group.settings.s1)
    assert_equal(true, group.settings.s2)
    assert_equal(false, group.settings.s3)
    
    # delete s3
    group.settings.s3 = nil
    assert_equal(2, group.custom_settings.all.size)
    assert_equal(false, group.custom_settings.has_setting?(:s3))
    assert_equal(nil, group.settings.s3)
    
    # same settings, referenced through different accessor
    group.custom_settings.s1 = 'bar'
    group.custom_settings.s3 = 123
    assert_equal(3, group.custom_settings.all.size)
    assert_equal('bar', group.custom_settings.s1)
    assert_equal(true, group.custom_settings.s2)
    assert_equal(123, group.custom_settings.s3)
  end

  def test_group_settings_inheritance
    group = Group.create

    Setting.global.message = 'dear aunt'
    Setting.global.message2 = 'test'
    group.settings.message = 'lets set so double'
    assert_equal('dear aunt', Setting.global.message)
    assert_equal('lets set so double', group.settings.message)
    
    assert_equal(2, group.settings.all.size)
    assert_equal(true, group.settings.has_setting?(:message2))
    
    Setting.global.message = nil
    assert_equal(nil, Setting.global.message)
    assert_equal('lets set so double', group.settings.message)
    
    Setting.global.message = 'delete select all!'
    assert_equal('lets set so double', group.settings.message)
    assert_equal('delete select all!', Setting.global.message)
    
    group.settings.message = nil
    assert_equal(true, group.settings.has_setting?(:message))
    assert_equal('delete select all!', group.settings.message)
    
    Setting.global.message = 'bah'
    assert_equal('bah', group.settings.message)
    
    Setting.global.message = nil
    assert_equal(nil, group.settings.message)
    
    group.settings.message = 'meh'
    assert_equal('meh', group.settings.message)
    
    Setting.global.message = 'so double the killer'
    assert_equal('meh', group.settings.message)

    assert_equal(2, Setting.global.all.size)
    
    assert_equal(2, group.settings.all.size)
    assert_equal(true, group.settings.has_setting?(:message2))
    
    assert_equal(1, group.settings.all(false).size)
    assert_equal(false, group.settings.has_setting?(:message2, false))
    
    assert_equal(2, group.custom_settings.all.size)
    assert_equal(true, group.custom_settings.has_setting?(:message2))
    
    assert_equal(1, group.custom_settings.all(false).size)
    assert_equal(false, group.custom_settings.has_setting?(:message2, false))
  end
  
  def test_user_settings
    group = Group.create
    user = group.users.create
    now = DateTime.now.to_s
    
    assert(user.settings.all.empty?)
    user.settings.s1 = 'double the killer'
    user.settings.s2 = now
    assert_equal(2, user.settings.all.size)
    assert_equal('double the killer', user.settings.s1)
    assert_equal(now, user.settings.s2)

    # same settings, but different accessor without inheritance
    user.private_settings.one = 1
    user.private_settings.two = 2
    user.private_settings.now = now
    # +2 more were set through settings
    assert_equal(5, user.private_settings.all.size)
    assert_equal(1, user.private_settings.one)
    assert_equal(2, user.private_settings.two)
    assert_equal(now, user.private_settings.now)
    assert_equal('double the killer', user.private_settings.s1)
    
    # delete now
    user.private_settings.now = nil
    assert_equal(4, user.settings.all.size)
    assert_equal(nil, user.settings.now)
    assert_equal(false, user.settings.has_setting?(:now))
  end
  
  def test_user_settings_inheritance
    group = Group.create
    user = group.users.create
    now = DateTime.now.to_s

    Setting.global.message = 'dear aunt'
    group.settings.message = 'lets set so double the killer delete select all!'
    group.settings.now = now
    assert_equal('dear aunt', Setting.global.message)
    assert_equal('lets set so double the killer delete select all!', group.settings.message)
    
    Setting.global.message = nil
    assert_equal(nil, Setting.global.message)
    # should be inherited from group
    assert_equal('lets set so double the killer delete select all!', user.settings.message)
    assert_equal('lets set so double the killer delete select all!', user.group_custom_settings.message)
    # should be inherited from global settings
    assert_equal(nil, user.without_group.message)
    # should be nil as we didn't set it for user
    assert_equal(nil, user.private_settings.message)
    assert_equal(nil, user.private_settings.now)
    # should be the same as on group level as we didn't set it for user
    assert_equal(now, user.settings.now)
    assert_equal(now, user.group_custom_settings.now)
    
    Setting.global.message = 'blah blah'
    # should be inherited from group
    assert_equal('lets set so double the killer delete select all!', user.settings.message)
    assert_equal('lets set so double the killer delete select all!', user.group_custom_settings.message)
    # should be inherited from global settings
    assert_equal('blah blah', user.without_group.message)
    # should be nil as we didn't set it for user
    assert_equal(nil, user.private_settings.message)

    group.settings.message = 'foo bar baz'
    # should be inherited from group
    assert_equal('foo bar baz', user.settings.message)
    assert_equal('foo bar baz', user.group_custom_settings.message)
    # should be inherited from global settings
    assert_equal('blah blah', user.without_group.message)
    # should be nil as we didn't set it for user
    assert_equal(nil, user.private_settings.message)
    
    user.settings.message = 'trustno1'
    # should override inherited group settings
    assert_equal('trustno1', user.settings.message)
    # should override inherited global settings too
    assert_equal('trustno1', user.without_group.message)
    # should be the same through both accessors
    assert_equal('trustno1', user.private_settings.message)
    assert_equal('trustno1', user.settings.message)
    assert_equal('trustno1', user.group_custom_settings.message)
  end
end