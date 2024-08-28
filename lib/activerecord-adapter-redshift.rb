require "active_record"
require "active_record/connection_adapters"
ActiveRecord::ConnectionAdapters.register("redshift", "ActiveRecord::ConnectionAdapters::RedshiftAdapter", "active_record/connection_adapters/redshift_adapter")
