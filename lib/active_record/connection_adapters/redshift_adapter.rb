# frozen_string_literal: true

require 'pg'

if ActiveRecord.version >= Gem::Version.new('7.1.0')
  require_relative 'redshift_7_1_adapter'
elsif ActiveRecord.version >= Gem::Version.new('7.0.0')
  require_relative 'redshift_7_0_adapter'
else
  raise 'no compatible version of ActiveRecord detected'
end

if ActiveRecord.version >= Gem::Version.new('7.2.0')
  ActiveRecord::ConnectionAdapters.register('redshift', 'ActiveRecord::ConnectionAdapters::RedshiftAdapter', 'active_record/connection_adapters/redshift_adapter')
end
