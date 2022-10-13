# frozen_string_literal: true

# Instead of updating the counter cache on the parent row, this change creates a new row in a
# counter cache table and updates the counter cache getter on the parent row to sum the values
# in the new table plus the value in the counter cache column.
#
# The following is required to enable this functionality for a given counter cache,
# otherwise it uses the default counter_cache functionality.

# For an counter cache named :engines_count on the :cars table you need to have a new table named
# with the following convention: <parent_table_name>_<counter_cache_name>s
# It needs two columns, parent_id and increment_by
#
# create_table :cars_engines_counts, force: true do |t|
#     t.integer :parent_id
#     t.integer :increment_by
#   end
#
# add_index :cars_engines_counts, :parent_id
#
# and then in the car model add the counter_cache_override option.
#
# Additionally, you will need to update, spec/db/database_spec to add your new table to table_allow_lists specifying that it does not have a timestamp.
#
# On the has_many relationship in the parent table specify the new option: counter_cache_override
# with the name of the counter_cache column. This will enable the override of the getter so that it
# checks the rows in the new table plus the value in the counter cache column for the total count. It also
# no longer updates the counter cache column but instead appends new rows to the table.
#
# has_many :engines, :dependent => :destroy, inverse_of: :my_car, counter_cache_override: :engines_count
#
# A separate job will periodically delete rows from the counter cache tables and update the row counter cache column.


module CounterCacheOverride
  module GetterAccessors
    def define_accessors(model, reflection)
      super
      define_counter_cache_getter_override(model, reflection)
    end

    def define_counter_cache_getter_override(model, reflection)
      cc_getter = reflection.options[:counter_cache_override].to_s
      if cc_getter.present?
        model.send(:define_method, cc_getter) do
          sql = "select sum(increment_by) as sum from #{model.table_name}_#{cc_getter}s where parent_id = :id"
          sum = ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.send(:sanitize_sql_array,[sql, id: id]))[0]["sum"].to_i
          self.read_attribute(cc_getter).to_i + sum unless read_attribute(cc_getter).nil? && sum == 0
        end
      end
    end
  end
end
ActiveRecord::Associations::Builder::Association.singleton_class.prepend CounterCacheOverride::GetterAccessors

module CounterCacheOverride
  module CounterCache
    extend ActiveSupport::Concern
    module ClassMethods

      def reset_counters(id, *counters, touch: nil)
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

          updates = { counter_name => object.send(counter_association).count(:all) }

          if touch
            names = touch if touch != true
            names = Array.wrap(names)
            options = names.extract_options!
            touch_updates = touch_attributes_with_time(*names, **options)
            updates.merge!(touch_updates)
          end

          unscoped.where(primary_key => object.id).update_all(updates)
          counter_table_name = "#{table_name}_#{counter_name}s"
          Array.wrap(id).each do |idx|
            sql = "delete from  #{counter_table_name} where parent_id=:parent_id"
            connection.exec_query(sanitize_sql_array([sql, parent_id: idx]))
          end
        end
        return true
      end

      def update_counters(id, counters)

        super(id, counters_with_default(counters)) unless counters_with_default(counters_without_touch(counters)).empty?

        counters_using_override(counters.except(:touch)).map do |counter_name, value|
          counter_table_name = "#{table_name}_#{counter_name}s"
          operator = value < 0 ? '-' : '+'
          Array.wrap(id).each do |idx|
            sql = "insert into #{counter_table_name}(parent_id, increment_by) values(:idx, :increment_by)"
            # ISSUE: This next line is a bit of a hack because of how in memory decrements work
            value = value == 0 ? -1 : value
            connection.exec_query(sanitize_sql_array([sql, idx: idx, increment_by: value]))
          end
        end
      end

      private
      def counters_without_touch(counters)
        hsh = counters.clone
        hsh.delete(:touch)
        hsh
      end

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
      count = count_records_rails_5

      # If there's nothing in the database and @target has no new records
      # we are certain the current target is an empty array. This is a
      # documented side-effect of the method that may avoid an extra SELECT.
      @target ||= [] and loaded! if count == 0

      [association_scope.limit_value, count].compact.min
    end

    def count_records_rails_5
      if reflection.has_cached_counter? &&
         reflection.options[:counter_cache_override].to_s == reflection.counter_cache_column.to_s
        owner.send(reflection.counter_cache_column.to_sym) || 0
      elsif reflection.has_cached_counter?
        # to_i added to fix bug in rails 5.0 - https://github.com/rails/rails/issues/28579
        owner._read_attribute(reflection.counter_cache_column).to_i
      else
        scope.count(:all)
      end
    end

    def update_counter_in_memory(difference, reflection = reflection())
      if reflection.counter_must_be_updated_by_has_many?
        counter = reflection.counter_cache_column
        return if counter.to_s == reflection.options[:counter_cache_override].to_s
        owner.increment(counter, difference)
        owner.send(:clear_attribute_change, counter) # eww
      end
    end
  end
end
ActiveRecord::Associations::HasManyAssociation.prepend CounterCacheOverride::HasManyCounts

module CounterCacheOverride
  module ValidOptions
    def valid_options(options)
      super + [:counter_cache_override]
    end
  end
end

ActiveRecord::Associations::Builder::HasMany.singleton_class.prepend CounterCacheOverride::ValidOptions

module CounterCacheOverride
  module Persistence
    def increment!(attribute, by = 1, touch: nil)
      if _reflections.values.map{ |ref| ref.options[:counter_cache_override] }.compact.map(&:to_s).include?(attribute.to_s)
        self.class.update_counters(id, attribute => by, :touch => touch)
      else
        increment(attribute, by)
        change = public_send(attribute) - (attribute_in_database(attribute.to_s) || 0)
        self.class.update_counters(id, attribute => change, touch: touch)
        clear_attribute_change(attribute) # eww
      end
      self
    end
  end
end
ActiveRecord::Persistence.prepend CounterCacheOverride::Persistence
