class Aircraft < ActiveRecord::Base
  self.pluralize_table_names = false
  has_many :engines, :foreign_key => "car_id"
  has_many :wheels, as: :wheelable

  def wheels_counts
    sum = ActiveRecord::Base.connection.execute("select sum(increment) as sum from aircraft_wheels_counts where parent_id = #{id}")[0]["sum"].to_i
    self.read_attribute(:wheels_count) + sum
  end
end
