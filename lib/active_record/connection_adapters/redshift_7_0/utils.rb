# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Redshift
      # Value Object to hold a schema qualified name.
      # This is usually the name of a PostgreSQL relation but it can also represent
      # schema qualified type names. +schema+ and +identifier+ are unquoted to prevent
      # double quoting.
      class Name # :nodoc:
        SEPARATOR = '.'
        attr_reader :schema, :identifier

        def initialize(schema, identifier)
          @schema = unquote(schema)
          @identifier = unquote(identifier)
        end

        def to_s
          parts.join SEPARATOR
        end

        def quoted
          if schema
            PG::Connection.quote_ident(schema) << SEPARATOR << PG::Connection.quote_ident(identifier)
          else
            PG::Connection.quote_ident(identifier)
          end
        end

        def ==(other)
          other.class == self.class && other.parts == parts
        end
        alias eql? ==

        def hash
          parts.hash
        end

        protected

        def unquote(part)
          if part&.start_with?('"')
            part[1..-2]
          else
            part
          end
        end

        def parts
          @parts ||= [@schema, @identifier].compact
        end
      end

      module Utils # :nodoc:
        module_function

        # Returns an instance of <tt>ActiveRecord::ConnectionAdapters::PostgreSQL::Name</tt>
        # extracted from +string+.
        # +schema+ is nil if not specified in +string+.
        # +schema+ and +identifier+ exclude surrounding quotes (regardless of whether provided in +string+)
        # +string+ supports the range of schema/table references understood by PostgreSQL, for example:
        #
        # * <tt>table_name</tt>
        # * <tt>"table.name"</tt>
        # * <tt>schema_name.table_name</tt>
        # * <tt>schema_name."table.name"</tt>
        # * <tt>"schema_name".table_name</tt>
        # * <tt>"schema.name"."table name"</tt>
        def extract_schema_qualified_name(string)
          schema, table = string.scan(/[^".\s]+|"[^"]*"/)
          if table.nil?
            table = schema
            schema = nil
          end
          Redshift::Name.new(schema, table)
        end
      end
    end
  end
end
