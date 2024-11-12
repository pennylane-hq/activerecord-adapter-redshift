# frozen_string_literal: true

require 'pg'

require_relative "../tasks/redshift_tasks"

if ActiveRecord.version >= Gem::Version.new('8.0.0')
  require_relative 'redshift_8_0_adapter'
elsif ActiveRecord.version >= Gem::Version.new('7.2.0')
  require_relative 'redshift_7_2_adapter'
elsif ActiveRecord.version >= Gem::Version.new('7.1.0')
  require_relative 'redshift_7_1_adapter'
elsif ActiveRecord.version >= Gem::Version.new('7.0.0')
  require_relative 'redshift_7_0_adapter'
else
  raise 'no compatible version of ActiveRecord detected'
end
