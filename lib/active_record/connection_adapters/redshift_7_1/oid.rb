# frozen_string_literal: true

require_relative 'oid/date_time'
require_relative 'oid/decimal'
require_relative 'oid/json'
require_relative 'oid/jsonb'

require_relative 'oid/type_map_initializer'

module ActiveRecord
  module ConnectionAdapters
    module Redshift
      module OID # :nodoc:
      end
    end
  end
end
