module Praxis::Mapper
  module Query

    # Abstract base class for assembling read queries for a data store.
    # May be implemented for SQL, CQL, etc.
    # Collects query statistics.
    #
    # @see lib/support/memory_query.rb
    class Base
      MULTI_GET_BATCH_SIZE = 4_096

      attr_reader :identity_map, :model, :statistics, :contexts
      attr_writer :where

      # Sets up a read query.
      #
      # @param identity_map [Praxis::Mapper::IdentityMap] handle to a Praxis::Mapper identity map
      # @param model [Praxis::Mapper::Model] handle to a Praxis::Mapper model
      # @param &block [Block] will be instance_eval'ed here
      def initialize(identity_map, model, &block)
        @identity_map = identity_map
        @model = model

        @select = nil

        @where = nil

        @limit = nil
        @track = Set.new
        @load = Set.new
        @contexts = Set.new

        @statistics = Hash.new(0) # general-purpose hash

        if block_given?
          self.instance_eval(&block)
        end
      end

      # @return handle to configured data store
      def connection
        identity_map.connection(model.repository_name)
      end

      # Gets or sets an SQL-like 'SELECT' clause to this query.
      # TODO: fix any specs or code that uses alias
      #
      # @param *fields [Array] list of fields, of type Symbol, String, or Hash
      # @return [Hash] current list of fields
      #
      # @example select(:account_id, "user_id", {"create_time" => :created_at})
      def select(*fields)
        if fields.any?
          @select = {} if @select.nil?
          fields.each do |field|
            case field
            when Symbol, String
              @select[field] = nil
            when Hash
              field.each do |alias_name, column_name|
                @select[alias_name] = column_name
              end
            else
              raise "unknown field type: #{field.class.name}"
            end
          end
        else
          return @select
        end
      end


      # Gets or sets an SQL-like 'WHERE' clause to this query.
      #
      # @param value [String] a 'WHERE' clause
      #
      # @example where("deployment_id=2")
      def where(value=nil)
        if value
          @where = value
        else
          return @where
        end
      end

      # Gets or sets an SQL-like 'LIMIT' clause to this query.
      #
      # @param value [String] a 'LIMIT' clause
      #
      # @example limit("LIMIT 10 OFFSET 20")
      def limit(value=nil)
        if value
          @limit = value
        else
          return @limit
        end
      end

      # @param *values [Array] a list of associations to track
      def track(*values, &block)
        if values.any?
          if block_given?
            raise "block and multiple values not supported" if values.size > 1
            @track << [values.first, block]
          else
            @track.merge(values)
          end
        else
          return @track
        end
      end

      # @param *values [Array] a list of associations to load immediately after this
      def load(*values, &block)
        if values.any?
          if block_given?
            raise "block and multiple values not supported" if values.size > 1
            @load << [values.first, block]
          else
            @load.merge(values)
          end
        else
          return @load
        end
      end

      def context(name=nil)
        @contexts << name
        spec = model.contexts.fetch(name) do
          raise "context #{name.inspect} not found for #{model}"
        end

        select *spec[:select]
        track *spec[:track]
      end


      # @return [Array] a list of associated models
      def tracked_associations
        track.collect do |(name, _)|
          model.associations.fetch(name) do
            raise "association #{name.inspect} not found for #{model}"
          end
        end.uniq
      end

      # Executes multi-get read query and returns all matching records.
      #
      # @param identity [Symbol|Array] a simple or composite key for this model
      # @param values [Array] list of identifier values (ideally a sorted set)
      # @return [Array] list of matching records, wrapped as models
      def multi_get(identity, values, select: nil)
        if self.frozen?
          raise TypeError.new "can not reuse a frozen query"
        end

        statistics[:multi_get] += 1

        records = []

        original_select = @select
        self.select *select.flatten.uniq if select

        values.each_slice(MULTI_GET_BATCH_SIZE) do |batch|
          # create model objects for each row
          records += _multi_get(identity, batch)
        end

        statistics[:records_loaded] += records.size
        records
      ensure
        @select = original_select unless self.frozen?
      end

      # Executes assembled read query and returns all matching records.
      #
      # @return [Array] list of matching records, wrapped as models
      def execute
        if self.frozen?
          raise TypeError.new "can not reuse a frozen query"
        end
        statistics[:execute] += 1

        rows = _execute

        statistics[:records_loaded] += rows.size
        rows.collect do |row|
          m = model.new(row)
          m._query = self
          m
        end
      end


      # Subclasses Must Implement
      def _multi_get(identity, values)
        raise "subclass responsibility"
      end

      # Subclasses Must Implement
      def _execute
        raise "subclass responsibility"
      end

      # Subclasses Must Implement
      # the sql or "sql-like" representation of the query
      def describe
        raise "subclass responsibility"
      end

    end
  end
end
