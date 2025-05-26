require_relative 'activerecord/test/cases/helper'

post = Post.find(1)
puts "Post ID: #{post.id}"
puts "comments_count: #{post.comments_count}"
puts "legacy_comments_count: #{post.legacy_comments_count}"
puts "comments.count: #{post.comments.count}"
puts "comments.size: #{post.comments.size}"
puts "comments.empty?: #{post.comments.empty?}"
puts "comments loaded?: #{post.comments.loaded?}"

# Check the reflection
reflection = Post.reflect_on_association(:comments)
puts "reflection.counter_cache_column: #{reflection.counter_cache_column}"
puts "reflection.has_cached_counter?: #{reflection.has_cached_counter?}"
puts "reflection.options[:counter_cache_override]: #{reflection.options[:counter_cache_override].inspect}"