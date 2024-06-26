# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Redshift
      class TypeMetadata < DelegateClass(SqlTypeMetadata)
        attr_reader :oid, :fmod, :array

        def initialize(type_metadata, oid: nil, fmod: nil)
          super(type_metadata)
          @type_metadata = type_metadata
          @oid = oid
          @fmod = fmod
          @array = /\[\]$/ === type_metadata.sql_type
        end

        def sql_type
          super.gsub(/\[\]$/, '')
        end

        def ==(other)
          other.is_a?(Redshift::TypeMetadata) &&
            attributes_for_hash == other.attributes_for_hash
        end
        alias eql? ==

        def hash
          attributes_for_hash.hash
        end

        protected

        def attributes_for_hash
          [self.class, @type_metadata, oid, fmod]
        end
      end
    end
  end
end
