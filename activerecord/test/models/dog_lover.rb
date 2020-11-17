class DogLover < ActiveRecord::Base
  has_many :trained_dogs, class_name: "Dog", foreign_key: :trainer_id, dependent: :destroy, counter_cache_override: :trained_dogs_count
  has_many :bred_dogs, class_name: "Dog", foreign_key: :breeder_id, counter_cache_override: :bred_dogs_count
  has_many :dogs, counter_cache_override: :dogs_count
end
