class DogLover < ActiveRecord::Base
  has_many :trained_dogs, class_name: "Dog", foreign_key: :trainer_id, dependent: :destroy
  has_many :bred_dogs, class_name: "Dog", foreign_key: :breeder_id
  has_many :dogs

  def trained_dogs_count
    puts "++++++++++++"
    puts ActiveRecord::Base.connection.execute("select sum(increment) as sum from dog_lovers_trained_dogs_counts where parent_id = #{id}")[0]["sum"].to_i
    puts "++++++++++++"
    sum = ActiveRecord::Base.connection.execute("select sum(increment) as sum from dog_lovers_trained_dogs_counts where parent_id = #{id}")[0]["sum"].to_i
    self.read_attribute(:trained_dogs_count) + sum
  end

  def bred_dogs_count
    puts "++++++++++++"
    puts ActiveRecord::Base.connection.execute("select sum(increment) as sum from dog_lovers_bred_dogs_counts where parent_id = #{id}")[0]["sum"].to_i
    puts "++++++++++++"
    sum = ActiveRecord::Base.connection.execute("select sum(increment) as sum from dog_lovers_bred_dogs_counts where parent_id = #{id}")[0]["sum"].to_i
    self.read_attribute(:bred_dogs_count) + sum
  end
end
