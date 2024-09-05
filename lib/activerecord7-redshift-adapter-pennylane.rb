module Activerecord7RedshiftAdapterPennylane
  class Railtie < ::Rails::Railtie
    initializer "activerecord7-redshift-adapter-pennylane.setup" do
      ActiveSupport.on_load(:active_record) do
        # The adapter registration API was introduced in Rails 7.2.0 in
        # https://github.com/rails/rails/commit/009c7e74117690f0dbe200188a929b345c9306c1
        next unless ActiveRecord.version >= Gem::Version.new('7.2.0')

        ActiveRecord::ConnectionAdapters.register('redshift', 'ActiveRecord::ConnectionAdapters::RedshiftAdapter')
      end
    end
  end
end
