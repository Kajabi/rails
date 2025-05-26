# frozen_string_literal: true

class Subscriber < ActiveRecord::Base
  self.primary_key = "nick"
  has_many :subscriptions, counter_cache_override: :books_count
  has_many :books, through: :subscriptions
end

class SpecialSubscriber < Subscriber
end
