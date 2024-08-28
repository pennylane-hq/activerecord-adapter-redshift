# frozen_string_literal: true

require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/statement_pool'

require 'active_record/connection_adapters/redshift_7_2/utils'
require 'active_record/connection_adapters/redshift_7_2/column'
require 'active_record/connection_adapters/redshift_7_2/oid'
require 'active_record/connection_adapters/redshift_7_2/quoting'
require 'active_record/connection_adapters/redshift_7_2/referential_integrity'
require 'active_record/connection_adapters/redshift_7_2/schema_definitions'
require 'active_record/connection_adapters/redshift_7_2/schema_dumper'
require 'active_record/connection_adapters/redshift_7_2/schema_statements'
require 'active_record/connection_adapters/redshift_7_2/type_metadata'
require 'active_record/connection_adapters/redshift_7_2/database_statements'

require 'active_record/tasks/database_tasks'

require 'pg'

require 'ipaddr'

ActiveRecord::Tasks::DatabaseTasks.register_task(/redshift/, 'ActiveRecord::Tasks::PostgreSQLDatabaseTasks')
module ActiveRecord
  module ConnectionHandling # :nodoc:

    def redshift_adapter_class
      ConnectionAdapters::RedshiftAdapter
    end

    # Establishes a connection to the database that's used by all Active Record objects
    def redshift_connection(config)
      redshift_adapter_class.new(config)
    end
  end

  module ConnectionAdapters
    # The PostgreSQL adapter works with the native C (https://bitbucket.org/ged/ruby-pg) driver.
    #
    # Options:
    #
    # * <tt>:host</tt> - Defaults to a Unix-domain socket in /tmp. On machines without Unix-domain sockets,
    #   the default is to connect to localhost.
    # * <tt>:port</tt> - Defaults to 5432.
    # * <tt>:username</tt> - Defaults to be the same as the operating system name of the user running the application.
    # * <tt>:password</tt> - Password to be used if the server demands password authentication.
    # * <tt>:database</tt> - Defaults to be the same as the user name.
    # * <tt>:schema_search_path</tt> - An optional schema search path for the connection given
    #   as a string of comma-separated schema names. This is backward-compatible with the <tt>:schema_order</tt> option.
    # * <tt>:encoding</tt> - An optional client encoding that is used in a <tt>SET client_encoding TO
    #   <encoding></tt> call on the connection.
    # * <tt>:min_messages</tt> - An optional client min messages that is used in a
    #   <tt>SET client_min_messages TO <min_messages></tt> call on the connection.
    # * <tt>:variables</tt> - An optional hash of additional parameters that
    #   will be used in <tt>SET SESSION key = val</tt> calls on the connection.
    # * <tt>:insert_returning</tt> - Does nothing for Redshift.
    #
    # Any further options are used as connection parameters to libpq. See
    # http://www.postgresql.org/docs/9.1/static/libpq-connect.html for the
    # list of parameters.
    #
    # In addition, default connection parameters of libpq can be set per environment variables.
    # See http://www.postgresql.org/docs/9.1/static/libpq-envars.html .
    class RedshiftAdapter < AbstractAdapter
      ADAPTER_NAME = 'Redshift'

      RS_VALID_CONN_PARAMS = %i[host hostaddr port dbname user password connect_timeout
                              client_encoding options application_name fallback_application_name
                              keepalives keepalives_idle keepalives_interval keepalives_count
                              tty sslmode requiressl sslcompression sslcert sslkey
                              sslrootcert sslcrl requirepeer krbsrvname gsslib service].freeze

      NATIVE_DATABASE_TYPES = {
        primary_key: 'integer identity primary key',
        string: { name: 'varchar' },
        text: { name: 'varchar' },
        integer: { name: 'integer' },
        float: { name: 'decimal' },
        decimal: { name: 'decimal' },
        datetime: { name: 'timestamp' },
        time: { name: 'timestamp' },
        date: { name: 'date' },
        bigint: { name: 'bigint' },
        boolean: { name: 'boolean' }
      }.freeze

      OID = Redshift::OID # :nodoc:

      include Redshift::Quoting
      include Redshift::ReferentialIntegrity
      include Redshift::SchemaStatements
      include Redshift::DatabaseStatements

      def schema_creation # :nodoc:
        Redshift::SchemaCreation.new self
      end

      def supports_index_sort_order?
        false
      end

      def supports_partial_index?
        false
      end

      def supports_transaction_isolation?
        false
      end

      def supports_foreign_keys?
        true
      end

      def supports_deferrable_constraints?
        false
      end

      def supports_views?
        true
      end

      def supports_virtual_columns?
        false
      end

      def index_algorithms
        { concurrently: 'CONCURRENTLY' }
      end

      class StatementPool < ConnectionAdapters::StatementPool # :nodoc:
        def initialize(connection, max)
          super(max)
          @raw_connection = connection
          @counter = 0
        end

        def next_key
          "a#{@counter += 1}"
        end

        private

        def dealloc(key)
          # This is ugly, but safe: the statement pool is only
          # accessed while holding the connection's lock. (And we
          # don't need the complication of with_raw_connection because
          # a reconnect would invalidate the entire statement pool.)
          if conn = @connection.instance_variable_get(:@raw_connection)
            conn.query "DEALLOCATE #{key}" if conn.status == PG::CONNECTION_OK
          end
        rescue PG::Error
        end
      end

      class << self
        def new_client(conn_params)
          PG.connect(**conn_params)
        rescue ::PG::Error => error
          if conn_params && conn_params[:dbname] == "postgres"
            raise ActiveRecord::ConnectionNotEstablished, error.message
          elsif conn_params && conn_params[:dbname] && error.message.include?(conn_params[:dbname])
            raise ActiveRecord::NoDatabaseError.db_error(conn_params[:dbname])
          elsif conn_params && conn_params[:user] && error.message.include?(conn_params[:user])
            raise ActiveRecord::DatabaseConnectionError.username_error(conn_params[:user])
          elsif conn_params && conn_params[:host] && error.message.include?(conn_params[:host])
            raise ActiveRecord::DatabaseConnectionError.hostname_error(conn_params[:host])
          else
            raise ActiveRecord::ConnectionNotEstablished, error.message
          end
        end
      end

      # Initializes and connects a PostgreSQL adapter.
      def initialize(...)
        super

        conn_params = @config.compact

        # Map ActiveRecords param names to PGs.
        conn_params[:user] = conn_params.delete(:username) if conn_params[:username]
        conn_params[:dbname] = conn_params.delete(:database) if conn_params[:database]

        # Forward only valid config params to PG::Connection.connect.
        conn_params.slice!(*RS_VALID_CONN_PARAMS)

        @connection_parameters = conn_params

        @max_identifier_length = nil
        @type_map = nil
        @raw_connection = nil
        @notice_receiver_sql_warnings = []
        @table_alias_length = nil

        @use_insert_returning = @config.key?(:insert_returning) ? self.class.type_cast_config_to_boolean(@config[:insert_returning]) : true
      end

      def truncate(table_name, name = nil)
        exec_query "TRUNCATE TABLE #{quote_table_name(table_name)}", name, []
      end

      # Is this connection alive and ready for queries?
      def active?
        @lock.synchronize do
          return false unless @raw_connection
          @raw_connection.query ";"
        end
        true
      rescue PG::Error
        false
      end

      def reload_type_map # :nodoc:
        @lock.synchronize do
          if @type_map
            type_map.clear
          else
            @type_map = Type::HashLookupTypeMap.new
          end

          initialize_type_map
        end
      end

      def reset!
        @lock.synchronize do
          return connect! unless @raw_connection

          unless @raw_connection.transaction_status == ::PG::PQTRANS_IDLE
            @raw_connection.query "ROLLBACK"
          end

          super
        end
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        @lock.synchronize do
          super
          @raw_connection&.close rescue nil
          @raw_connection = nil
        end
      end

      def discard! # :nodoc:
        super
        @raw_connection&.socket_io&.reopen(IO::NULL) rescue nil
        @raw_connection = nil
      end

      def native_database_types # :nodoc:
        NATIVE_DATABASE_TYPES
      end

      # Returns true, since this connection adapter supports migrations.
      def supports_migrations?
        true
      end

      # Does PostgreSQL support finding primary key on non-Active Record tables?
      def supports_primary_key? # :nodoc:
        true
      end

      def supports_ddl_transactions?
        true
      end

      def supports_explain?
        true
      end

      def supports_extensions?
        false
      end

      def supports_ranges?
        false
      end

      def supports_materialized_views?
        false
      end

      def supports_import?
        true
      end

      def enable_extension(name)
        ;
      end

      def disable_extension(name)
        ;
      end

      def extension_enabled?(_name)
        false
      end

      def supports_common_table_expressions?
        true
      end

      # Returns the configured supported identifier length supported by PostgreSQL
      def table_alias_length
        @table_alias_length ||= query('SHOW max_identifier_length', 'SCHEMA')[0][0].to_i
      end

      # Set the authorized user for this session
      def session_auth=(user)
        clear_cache!
        exec_query "SET SESSION AUTHORIZATION #{user}"
      end

      def use_insert_returning?
        false
      end

      def valid_type?(type)
        !native_database_types[type].nil?
      end

      def update_table_definition(table_name, base)
        # :nodoc:
        Redshift::Table.new(table_name, base)
      end

      def lookup_cast_type(sql_type)
        # :nodoc:
        oid = execute("SELECT #{quote(sql_type)}::regtype::oid", 'SCHEMA').first['oid'].to_i
        super(oid)
      end

      def column_name_for_operation(operation, _node)
        # :nodoc:
        OPERATION_ALIASES.fetch(operation) { operation.downcase }
      end

      OPERATION_ALIASES = { # :nodoc:
                            'maximum' => 'max',
                            'minimum' => 'min',
                            'average' => 'avg'
      }.freeze

      protected

      # Returns the version of the connected PostgreSQL server.
      def redshift_version
        @raw_connection.server_version
      end

      def translate_exception(exception, message:, sql:, binds:)
        return exception unless exception.respond_to?(:result)

        case exception.message
        when /duplicate key value violates unique constraint/
          RecordNotUnique.new(message, exception)
        when /violates foreign key constraint/
          InvalidForeignKey.new(message, exception)
        else
          super
        end
      end

      class << self
        def initialize_type_map(m)
          # :nodoc:
          m.register_type 'int2', Type::Integer.new(limit: 2)
          m.register_type 'int4', Type::Integer.new(limit: 4)
          m.register_type 'int8', Type::Integer.new(limit: 8)
          m.alias_type 'oid', 'int2'
          m.register_type 'float4', Type::Float.new
          m.alias_type 'float8', 'float4'
          m.register_type 'text', Type::Text.new
          register_class_with_limit m, 'varchar', Type::String
          m.alias_type 'char', 'varchar'
          m.alias_type 'name', 'varchar'
          m.alias_type 'bpchar', 'varchar'
          m.register_type 'bool', Type::Boolean.new
          m.alias_type 'timestamptz', 'timestamp'
          m.register_type 'date', Type::Date.new
          m.register_type 'time', Type::Time.new

          m.register_type 'timestamp' do |_, _, sql_type|
            precision = extract_precision(sql_type)
            OID::DateTime.new(precision: precision)
          end

          m.register_type 'numeric' do |_, fmod, sql_type|
            precision = extract_precision(sql_type)
            scale = extract_scale(sql_type)

            # The type for the numeric depends on the width of the field,
            # so we'll do something special here.
            #
            # When dealing with decimal columns:
            #
            # places after decimal  = fmod - 4 & 0xffff
            # places before decimal = (fmod - 4) >> 16 & 0xffff
            if fmod && (fmod - 4 & 0xffff) == 0
              # FIXME: Remove this class, and the second argument to
              # lookups on PG
              Type::DecimalWithoutScale.new(precision: precision)
            else
              OID::Decimal.new(precision: precision, scale: scale)
            end
          end
        end
      end

      private

      def get_oid_type(oid, fmod, column_name, sql_type = '')
        # :nodoc:
        load_additional_types(type_map, [oid]) unless type_map.key?(oid)

        type_map.fetch(oid, fmod, sql_type) do
          warn "unknown OID #{oid}: failed to recognize type of '#{column_name}'. It will be treated as String."
          Type::Value.new.tap do |cast_type|
            type_map.register_type(oid, cast_type)
          end
        end
      end

      def type_map
        @type_map ||= Type::HashLookupTypeMap.new
      end

      def initialize_type_map(m = type_map)
        self.class.initialize_type_map(m)
        load_additional_types(m)
      end

      def extract_limit(sql_type)
        # :nodoc:
        case sql_type
        when /^bigint/i, /^int8/i
          8
        when /^smallint/i
          2
        else
          super
        end
      end

      # Extracts the value from a PostgreSQL column default definition.
      def extract_value_from_default(default)
        # :nodoc:
        case default
          # Quoted types
        when /\A[(B]?'(.*)'::/m
          Regexp.last_match(1).gsub(/''/, "'")
          # Boolean types
        when 'true', 'false'
          default
          # Numeric types
        when /\A\(?(-?\d+(\.\d*)?)\)?\z/
          Regexp.last_match(1)
          # Object identifier types
        when /\A-?\d+\z/
          Regexp.last_match(1)
        else # rubocop:disable Style/EmptyElse
          # Anything else is blank, some user type, or some function
          # and we can't know the value of that, so return nil.
          nil
        end
      end

      def extract_default_function(default_value, default)
        # :nodoc:
        default if has_default_function?(default_value, default)
      end

      def has_default_function?(default_value, default)
        # :nodoc:
        !default_value && (/\w+\(.*\)/ === default)
      end

      def load_additional_types(type_map, oids = nil)
        # :nodoc:
        initializer = OID::TypeMapInitializer.new(type_map)

        load_types_queries(initializer, oids) do |query|
          execute_and_clear(query, 'SCHEMA', [], allow_retry: true, materialize_transactions: false) do |records|
            initializer.run(records)
          end
        end
      end

      def load_types_queries(_initializer, oids)
        query =
          if supports_ranges?
            <<-SQL
              SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput, r.rngsubtype, t.typtype, t.typbasetype
              FROM pg_type as t
              LEFT JOIN pg_range as r ON oid = rngtypid
            SQL
          else
            <<-SQL
              SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput, t.typtype, t.typbasetype
              FROM pg_type as t
            SQL
          end

        if oids
          yield query + 'WHERE t.oid::integer IN (%s)' % oids.join(', ')
        else
          yield query
        end
      end

      FEATURE_NOT_SUPPORTED = '0A000' # :nodoc:

      def execute_and_clear(sql, name, binds, prepare: false, async: false, allow_retry: false, materialize_transactions: true)
        sql = transform_query(sql)
        check_if_write_query(sql)

        if !prepare || without_prepared_statement?(binds)
          result = exec_no_cache(sql, name, binds, async: async, allow_retry: allow_retry, materialize_transactions: materialize_transactions)
        else
          result = exec_cache(sql, name, binds, async: async, allow_retry: allow_retry, materialize_transactions: materialize_transactions)
        end
        begin
          ret = yield result
        ensure
          result.clear
        end
        ret
      end

      def exec_no_cache(sql, name, binds, async:, allow_retry:, materialize_transactions:)
        mark_transaction_written_if_write(sql)

        # make sure we carry over any changes to ActiveRecord.default_timezone that have been
        # made since we established the connection
        update_typemap_for_default_timezone

        type_casted_binds = type_casted_binds(binds)
        log(sql, name, binds, type_casted_binds, async: async) do
          with_raw_connection do |conn|
            result = conn.exec_params(sql, type_casted_binds)
            verified!
            result
          end
        end
      end

      def exec_cache(sql, name, binds, async:, allow_retry:, materialize_transactions:)
        mark_transaction_written_if_write(sql)

        update_typemap_for_default_timezone

        with_raw_connection do |conn|
          stmt_key = prepare_statement(sql, binds, conn)
          type_casted_binds = type_casted_binds(binds)

          log(sql, name, binds, type_casted_binds, stmt_key, async: async) do
            result = conn.exec_prepared(stmt_key, type_casted_binds)
            verified!
            result
          end
        end
      rescue ActiveRecord::StatementInvalid => e
        raise unless is_cached_plan_failure?(e)

        # Nothing we can do if we are in a transaction because all commands
        # will raise InFailedSQLTransaction
        if in_transaction?
          raise ActiveRecord::PreparedStatementCacheExpired.new(e.cause.message)
        else
          @lock.synchronize do
            # outside of transactions we can simply flush this query and retry
            @statements.delete sql_key(sql)
          end
          retry
        end
      end

      # Annoyingly, the code for prepared statements whose return value may
      # have changed is FEATURE_NOT_SUPPORTED.
      #
      # This covers various different error types so we need to do additional
      # work to classify the exception definitively as a
      # ActiveRecord::PreparedStatementCacheExpired
      #
      # Check here for more details:
      # https://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/utils/cache/plancache.c#l573
      CACHED_PLAN_HEURISTIC = 'cached plan must not change result type'

      def is_cached_plan_failure?(e)
        pgerror = e.cause
        code = pgerror.result.result_error_field(PG::PG_DIAG_SQLSTATE)
        code == FEATURE_NOT_SUPPORTED && pgerror.message.include?(CACHED_PLAN_HEURISTIC)
      rescue StandardError
        false
      end

      # Returns the statement identifier for the client side cache
      # of statements
      def sql_key(sql)
        "#{schema_search_path}-#{sql}"
      end

      # Prepare the statement if it hasn't been prepared, return
      # the statement key.
      def prepare_statement(sql, binds, conn)
        sql_key = sql_key(sql)
        unless @statements.key? sql_key
          nextkey = @statements.next_key
          begin
            conn.prepare nextkey, sql
          rescue => e
            raise translate_exception_class(e, sql, binds)
          end
          # Clear the queue
          conn.get_last_result
          @statements[sql_key] = nextkey
        end
        @statements[sql_key]
      end

      # Connects to a PostgreSQL server and sets up the adapter depending on the
      # connected server's characteristics.
      def connect
        @raw_connection = self.class.new_client(@connection_parameters)
      rescue ConnectionNotEstablished => ex
        raise ex.set_pool(@pool)
      end

      def reconnect
        begin
          @raw_connection&.reset
        rescue PG::ConnectionBad
          @raw_connection = nil
        end

        connect unless @raw_connection
      end

      def reconnect
        begin
          @raw_connection&.reset
        rescue PG::ConnectionBad
          @raw_connection = nil
        end

        connect unless @raw_connection
      end

      # Configures the encoding, verbosity, schema search path, and time zone of the connection.
      # This is called by #connect and should not be called manually.
      def configure_connection
        if @config[:encoding]
          @raw_connection.set_client_encoding(@config[:encoding])
        end
        self.schema_search_path = @config[:schema_search_path] || @config[:schema_order]

        variables = @config.fetch(:variables, {}).stringify_keys

        # SET statements from :variables config hash
        # https://www.postgresql.org/docs/current/static/sql-set.html
        variables.map do |k, v|
          if [':default', :default].include?(v)
            # Sets the value to the global or compile default
            execute("SET #{k} TO DEFAULT", 'SCHEMA')
          elsif !v.nil?
            execute("SET #{k} TO #{quote(v)}", 'SCHEMA')
          end
        end

        add_pg_encoders
        add_pg_decoders

        reload_type_map
      end

      def reconfigure_connection_timezone
        variables = @config.fetch(:variables, {}).stringify_keys

        # If it's been directly configured as a connection variable, we don't
        # need to do anything here; it will be set up by configure_connection
        # and then never changed.
        return if variables["timezone"]

        # If using Active Record's time zone support configure the connection
        # to return TIMESTAMP WITH ZONE types in UTC.
        if default_timezone == :utc
          internal_execute("SET timezone TO 'UTC'")
        else
          internal_execute("SET timezone TO DEFAULT")
        end
      end

      def last_insert_id_result(sequence_name)
        # :nodoc:
        exec_query("SELECT currval('#{sequence_name}')", 'SQL')
      end

      # Returns the list of a table's column names, data types, and default values.
      #
      # The underlying query is roughly:
      #  SELECT column.name, column.type, default.value
      #    FROM column LEFT JOIN default
      #      ON column.table_id = default.table_id
      #     AND column.num = default.column_num
      #   WHERE column.table_id = get_table_id('table_name')
      #     AND column.num > 0
      #     AND NOT column.is_dropped
      #   ORDER BY column.num
      #
      # If the table name is not prefixed with a schema, the database will
      # take the first match from the schema search path.
      #
      # Query implementation notes:
      #  - format_type includes the column size constraint, e.g. varchar(50)
      #  - ::regclass is a function that gives the id for a table name
      def column_definitions(table_name)
        # :nodoc:
        query(<<-END_SQL, 'SCHEMA')
              SELECT a.attname, format_type(a.atttypid, a.atttypmod),
                     pg_get_expr(d.adbin, d.adrelid), a.attnotnull, a.atttypid, a.atttypmod
                FROM pg_attribute a LEFT JOIN pg_attrdef d
                  ON a.attrelid = d.adrelid AND a.attnum = d.adnum
               WHERE a.attrelid = '#{quote_table_name(table_name)}'::regclass
                 AND a.attnum > 0 AND NOT a.attisdropped
               ORDER BY a.attnum
        END_SQL
      end

      def extract_table_ref_from_insert_sql(sql)
        sql[/into\s("[A-Za-z0-9_."\[\]\s]+"|[A-Za-z0-9_."\[\]]+)\s*/im]
        Regexp.last_match(1)&.strip
      end

      def arel_visitor
        Arel::Visitors::PostgreSQL.new(self)
      end

      def build_statement_pool
        StatementPool.new(@raw_connection, self.class.type_cast_config_to_integer(@config[:statement_limit]))
      end

      def can_perform_case_insensitive_comparison_for?(column)
        @case_insensitive_cache ||= {}
        @case_insensitive_cache[column.sql_type] ||= begin
                                                       sql = <<~SQL
                                                         SELECT exists(
                                                           SELECT * FROM pg_proc
                                                           WHERE proname = 'lower'
                                                             AND proargtypes = ARRAY[#{quote column.sql_type}::regtype]::oidvector
                                                         ) OR exists(
                                                           SELECT * FROM pg_proc
                                                           INNER JOIN pg_cast
                                                             ON ARRAY[casttarget]::oidvector = proargtypes
                                                           WHERE proname = 'lower'
                                                             AND castsource = #{quote column.sql_type}::regtype
                                                         )
                                                       SQL
                                                       execute_and_clear(sql, 'SCHEMA', []) do |result|
                                                         result.getvalue(0, 0)
                                                       end
                                                     end
      end

      def add_pg_encoders
        map = PG::TypeMapByClass.new
        map[Integer] = PG::TextEncoder::Integer.new
        map[TrueClass] = PG::TextEncoder::Boolean.new
        map[FalseClass] = PG::TextEncoder::Boolean.new
        @raw_connection.type_map_for_queries = map
      end

      def update_typemap_for_default_timezone
        if @raw_connection && @mapped_default_timezone != default_timezone && @timestamp_decoder
          decoder_class = default_timezone == :utc ?
                            PG::TextDecoder::TimestampUtc :
                            PG::TextDecoder::TimestampWithoutTimeZone

          @timestamp_decoder = decoder_class.new(**@timestamp_decoder.to_h)
          @raw_connection.type_map_for_results.add_coder(@timestamp_decoder)

          @mapped_default_timezone = default_timezone

          # if default timezone has changed, we need to reconfigure the connection
          # (specifically, the session time zone)
          reconfigure_connection_timezone

          true
        end
      end

      def add_pg_decoders
        @default_timezone = nil
        @timestamp_decoder = nil

        coders_by_name = {
          'int2' => PG::TextDecoder::Integer,
          'int4' => PG::TextDecoder::Integer,
          'int8' => PG::TextDecoder::Integer,
          'oid' => PG::TextDecoder::Integer,
          'float4' => PG::TextDecoder::Float,
          'float8' => PG::TextDecoder::Float,
          'bool' => PG::TextDecoder::Boolean
        }

        if defined?(PG::TextDecoder::TimestampUtc)
          # Use native PG encoders available since pg-1.1
          coders_by_name['timestamp'] = PG::TextDecoder::TimestampUtc
          coders_by_name['timestamptz'] = PG::TextDecoder::TimestampWithTimeZone
        end

        known_coder_types = coders_by_name.keys.map { |n| quote(n) }
        query = <<~SQL % known_coder_types.join(', ')
          SELECT t.oid, t.typname
          FROM pg_type as t
          WHERE t.typname IN (%s)
        SQL
        coders = execute_and_clear(query, 'SCHEMA', [], allow_retry: true, materialize_transactions: false) do |result|
          result.filter_map { |row| construct_coder(row, coders_by_name[row['typname']]) }
        end

        map = PG::TypeMapByOid.new
        coders.each { |coder| map.add_coder(coder) }
        @raw_connection.type_map_for_results = map

        @type_map_for_results = PG::TypeMapByOid.new
        @type_map_for_results.default_type_map = map

        # extract timestamp decoder for use in update_typemap_for_default_timezone
        @timestamp_decoder = coders.find { |coder| coder.name == 'timestamp' }
        update_typemap_for_default_timezone
      end

      def construct_coder(row, coder_class)
        return unless coder_class

        coder_class.new(oid: row['oid'].to_i, name: row['typname'])
      end

      def create_table_definition(*args, **options)
        # :nodoc:
        Redshift::TableDefinition.new(self, *args, **options)
      end
    end
  end
end
