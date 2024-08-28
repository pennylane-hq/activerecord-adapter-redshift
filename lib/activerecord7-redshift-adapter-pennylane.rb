module Activerecord7RedshiftAdapterPennylane
  class Railtie < ::Rails::Railtie
    initializer "activerecord7-redshift-adapter-pennylane.setup" do
      ActiveSupport.on_load(:active_record) do
        ActiveRecord::ConnectionAdapters.register('redshift', 'ActiveRecord::ConnectionAdapters::RedshiftAdapter')
      end
    end
  end
end
