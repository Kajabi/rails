
if !ActiveRecord.gem_version.to_s.start_with?("5.0")
  ActiveSupport::Deprecation.warn("Counter Cache Override is only tested with rails 5.0")
end

module CounterCacheOverride
  module GetterAccessors
    def define_accessors(model, reflection)
      super
      define_counter_cache_getter_override(model, reflection)
    end

    def define_counter_cache_getter_override(model, reflection)
      cc_getter = reflection.options[:counter_cache_override].to_s
      model.send(:define_method, cc_getter) do
        sql = "select sum(increment) as sum from #{model.table_name}_#{cc_getter}s where parent_id = :id"
        sum = ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.send(:sanitize_sql_array,[sql, id: id]))[0]["sum"].to_i
        self.read_attribute(cc_getter).to_i + sum unless read_attribute(cc_getter).nil? && sum == 0
      end
    end
  end
end
ActiveRecord::Associations::Builder::Association.singleton_class.prepend CounterCacheOverride::GetterAccessors

module CounterCacheOverride
  module CounterCache
    extend ActiveSupport::Concern
    module ClassMethods
      def reset_counters(id, *counters)
        object = find(id)
        counters.each do |counter_association|
          has_many_association = _reflect_on_association(counter_association)
          unless has_many_association
            has_many = reflect_on_all_associations(:has_many)
            has_many_association = has_many.find { |association| association.counter_cache_column && association.counter_cache_column.to_sym == counter_association.to_sym }
            counter_association = has_many_association.plural_name if has_many_association
          end
          raise ArgumentError, "'#{self.name}' has no association called '#{counter_association}'" unless has_many_association

          if has_many_association.is_a? ActiveRecord::Reflection::ThroughReflection
            has_many_association = has_many_association.through_reflection
          end

          foreign_key  = has_many_association.foreign_key.to_s
          child_class  = has_many_association.klass
          reflection   = child_class._reflections.values.find { |e| e.belongs_to? && e.foreign_key.to_s == foreign_key && e.options[:counter_cache].present? }
          counter_name = reflection.counter_cache_column

          unscoped.where(primary_key => object.id).update_all(
            counter_name => object.send(counter_association).count(:all)
          )
          counter_table_name = "#{table_name}_#{counter_name}s"
          Array.wrap(id).each do |idx|
            sql = "delete from  #{counter_table_name} where parent_id=:parent_id"
            connection.exec_query(sanitize_sql_array([sql, parent_id: idx]))
          end
        end
        return true
      end

      def update_counters(id, counters)
        super(id, counters_with_default(counters)) unless counters_with_default(counters).empty?

        counters_using_override(counters).map do |counter_name, value|
          counter_table_name = "#{table_name}_#{counter_name}s"
          operator = value < 0 ? '-' : '+'
          Array.wrap(id).each do |idx|
            #sql = "insert into :counter_table_name(parent_id, increment) values(:idx, :increment_by)"
            sql = "insert into #{counter_table_name}(parent_id, increment) values(:idx, :increment_by)"
            # ISSUE: This next line is a bit of a hack because of how in memory decrements work
            value = value == 0 ? -1 : value
            connection.exec_query(sanitize_sql_array([sql, idx: idx, increment_by: value]))
          end
        end
      end

      private
      def counter_overrides
        # TODO memoize
        reflections.values.map{ |ref| ref.options[:counter_cache_override] }.compact.map(&:to_s)
      end

      def counters_using_override(counters)
        counters.select { |key,_|  counter_overrides.include?(key) }
      end

      def counters_with_default(counters)
        counters.reject { |key,_|  counter_overrides.include?(key) }
      end
    end
  end
end
ActiveRecord::Base.include CounterCacheOverride::CounterCache

module CounterCacheOverride
  module HasManyCounts

    private
    def count_records
     # byebug
      count = if has_cached_counter? &&
        reflection.options[:counter_cache_override].to_s == cached_counter_attribute_name.to_s
        owner.send(cached_counter_attribute_name.to_sym) || 0
      elsif has_cached_counter?
        owner._read_attribute cached_counter_attribute_name
      else
        scope.count
      end

      # If there's nothing in the database and @target has no new records
      # we are certain the current target is an empty array. This is a
      # documented side-effect of the method that may avoid an extra SELECT.
      @target ||= [] and loaded! if count == 0

      [association_scope.limit_value, count].compact.min
    end
    def update_counter_in_memory(difference, reflection = reflection())
      if counter_must_be_updated_by_has_many?(reflection)
        counter = cached_counter_attribute_name(reflection)
        return if counter.to_s == reflection.options[:counter_cache_override].to_s
        owner[counter] += difference
        owner.send(:clear_attribute_changes, counter) # eww
      end
    end
  end
end
ActiveRecord::Associations::HasManyAssociation.prepend CounterCacheOverride::HasManyCounts

module CounterCacheOverride
  module CounterCacheAvailableInMemory
    def counter_cache_available_in_memory?(counter_cache_name)
      counter_cache_overrides = target._reflections.values.map { |opt| opt.options.dig(:counter_cache_override) }.compact.map(&:to_s)
      target.respond_to?(counter_cache_name) && !counter_cache_overrides.include?(counter_cache_name)
    end
  end
end
ActiveRecord::Associations::BelongsToAssociation.prepend CounterCacheOverride::CounterCacheAvailableInMemory
module CounterCacheOverride
  module ValidOptions
    def valid_options
      super + [:counter_cache_override]
    end
  end
end
ActiveRecord::Associations::Builder::HasMany.prepend CounterCacheOverride::ValidOptions


module CounterCacheOverride
  module Persistence
    def increment!(attribute, by = 1)
      if _reflections.values.map{ |ref| ref.options[:counter_cache_override] }.compact.map(&:to_s).include?(attribute.to_s)
        self.class.update_counters(id, attribute => by)
      else
        increment(attribute, by)
        change = public_send(attribute) - (attribute_was(attribute.to_s) || 0)
        self.class.update_counters(id, attribute => change)
        clear_attribute_change(attribute) # eww
      end
      self
    end
  end
end
ActiveRecord::Persistence.prepend CounterCacheOverride::Persistence
