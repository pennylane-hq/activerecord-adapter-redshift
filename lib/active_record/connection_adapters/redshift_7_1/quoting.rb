# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Redshift
      module Quoting
        QUOTED_COLUMN_NAMES = Concurrent::Map.new # :nodoc:
        QUOTED_TABLE_NAMES = Concurrent::Map.new # :nodoc:

        # Escapes binary strings for bytea input to the database.
        def escape_bytea(value)
          valid_raw_connection.escape_bytea(value) if value
        end

        # Unescapes bytea output from a database to the binary string it represents.
        # NOTE: This is NOT an inverse of escape_bytea! This is only to be used
        # on escaped binary output from database drive.
        def unescape_bytea(value)
          valid_raw_connection.unescape_bytea(value) if value
        end

        # Quotes strings for use in SQL input.
        def quote_string(s) # :nodoc:
          with_raw_connection(allow_retry: true, materialize_transactions: false) do |connection|
            connection.escape(s)
          end
        end

        # Checks the following cases:
        #
        # - table_name
        # - "table.name"
        # - schema_name.table_name
        # - schema_name."table.name"
        # - "schema.name".table_name
        # - "schema.name"."table.name"
        def quote_table_name(name)
          QUOTED_TABLE_NAMES[name] ||= Utils.extract_schema_qualified_name(name.to_s).quoted.freeze
        end

        def quote_table_name_for_assignment(_table, attr)
          quote_column_name(attr)
        end

        # Quotes column names for use in SQL queries.
        def quote_column_name(name) # :nodoc:
          QUOTED_COLUMN_NAMES[name] ||= PG::Connection.quote_ident(super).freeze
        end

        # Quotes schema names for use in SQL queries.
        def quote_schema_name(name)
          PG::Connection.quote_ident(name)
        end

        # Quote date/time values for use in SQL input.
        def quoted_date(value) # :nodoc:
          if value.year <= 0
            bce_year = format("%04d", -value.year + 1)
            super.sub(/^-?\d+/, bce_year) + " BC"
          else
            super
          end
        end

        def quoted_binary(value) # :nodoc:
          "'#{escape_bytea(value.to_s)}'"
        end

        # Does not quote function default values for UUID columns
        def quote_default_value(value, column) # :nodoc:
          if column.type == :uuid && value =~ /\(\)/
            value
          else
            quote(value, column)
          end
        end

        def quote(value)
          case value
          when Numeric
            if value.finite?
              super
            else
              "'#{value}'"
            end
          when Type::Binary::Data
            "'#{escape_bytea(value.to_s)}'"
          else
            super
          end
        end

        def quote_default_expression(value, column) # :nodoc:
          if value.is_a?(Proc)
            value.call
          elsif column.type == :uuid && value.is_a?(String) && value.include?("()")
            value # Does not quote function default values for UUID columns
          else
            super
          end
        end

        def type_cast(value)
          case value
          when Type::Binary::Data
            # Return a bind param hash with format as binary.
            # See http://deveiate.org/code/pg/PGconn.html#method-i-exec_prepared-doc
            # for more information
            { value: value.to_s, format: 1 }
          else
            super
          end
        end

        def lookup_cast_type_from_column(column) # :nodoc:
          verify! if type_map.nil?
          type_map.lookup(column.oid, column.fmod, column.sql_type)
        end

        def column_name_matcher
          COLUMN_NAME
        end

        def column_name_with_order_matcher
          COLUMN_NAME_WITH_ORDER
        end

        COLUMN_NAME = /
          \A
          (
            (?:
              # "schema_name"."table_name"."column_name"::type_name | function(one or no argument)::type_name
              ((?:\w+\.|"\w+"\.){,2}(?:\w+|"\w+")(?:::\w+)? | \w+\((?:|\g<2>)\)(?:::\w+)?)
            )
            (?:(?:\s+AS)?\s+(?:\w+|"\w+"))?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix

        COLUMN_NAME_WITH_ORDER = /
          \A
          (
            (?:
              # "schema_name"."table_name"."column_name"::type_name | function(one or no argument)::type_name
              ((?:\w+\.|"\w+"\.){,2}(?:\w+|"\w+")(?:::\w+)? | \w+\((?:|\g<2>)\)(?:::\w+)?)
            )
            (?:\s+COLLATE\s+"\w+")?
            (?:\s+ASC|\s+DESC)?
            (?:\s+NULLS\s+(?:FIRST|LAST))?
          )
          (?:\s*,\s*\g<1>)*
          \z
        /ix

        private_constant :COLUMN_NAME, :COLUMN_NAME_WITH_ORDER

      end
    end
  end
end
