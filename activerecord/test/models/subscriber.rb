class Subscriber < ActiveRecord::Base
  self.primary_key = 'nick'
  has_many :subscriptions
  has_many :books, :through => :subscriptions, counter_cache_override: :books_count
end

class SpecialSubscriber < Subscriber
end
