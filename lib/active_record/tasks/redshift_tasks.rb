# frozen_string_literal: true

if ActiveRecord.version >= Gem::Version.new('7.2.0')
  require_relative 'redshift_7_2_tasks'
elsif ActiveRecord.version >= Gem::Version.new('7.1.0')
  require_relative 'redshift_7_1_tasks'
elsif ActiveRecord.version >= Gem::Version.new('7.0.0')
  require_relative 'redshift_7_0_tasks'
else
  raise 'no compatible version of ActiveRecord detected'
end
