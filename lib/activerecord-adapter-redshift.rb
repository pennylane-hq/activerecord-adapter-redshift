if ActiveRecord.version >= Gem::Version.new('7.2.0')
  require "active_record"
  require "active_record/connection_adapters"
  ActiveRecord::ConnectionAdapters.register("redshift", "ActiveRecord::ConnectionAdapters::RedshiftAdapter", "active_record/connection_adapters/redshift_adapter")
end
