class Subscriber < ActiveRecord::Base
  self.primary_key = 'nick'
  has_many :subscriptions
  has_many :books, :through => :subscriptions

  def books_count
    sql = "select sum(increment) as sum from subscribers_books_counts where parent_id = :id"
    sum = ActiveRecord::Base.connection.execute(ActiveRecord::Base.send(:sanitize_sql_array,[sql, id: id]))[0]["sum"].to_i
    read_attribute(:books_count) + sum
  end
end

class SpecialSubscriber < Subscriber
end
