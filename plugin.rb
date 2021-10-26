# frozen_string_literal: true

# name: discourse-url-filters
# about: Adds url query params for filtering topics
# version: 0.1
# authors: Blake Erickson
# url: https://github.com/discourse/discourse-url-filters

enabled_site_setting :url_filters_enabled

PLUGIN_NAME = "discourse_url_filters".freeze

after_initialize do

  if Discourse.has_needed_version?(Discourse::VERSION::STRING, '1.8.0.beta6')
    require_dependency 'topic_query'

    # After
    TopicQuery.add_custom_filter(:after) do |results, topic_query|
      if after = topic_query.options[:after]
        if (after = after.to_i) > 0
          results = results.where('topics.created_at > ?', after.days.ago)
        end
      end
      results
    end

    # Categories
    TopicQuery.add_custom_filter(:categories) do |results, topic_query|
      if categories_param = topic_query.options[:categories]
        categories = categories_param.split(',')
        category_ids = Category.where(slug: categories).pluck(:id)
        #results = results.where('topics.category_id = ?', category_ids)
        puts "CATEGORIES: #{category_ids}"

        results = results.where(<<~SQL, category_ids: category_ids)
        topics.category_id IN (:category_ids)
        SQL
      end
      results
    end

    # Include Tags
    # Using include_tags for now until we figure out why there are issues using
    # the existing tags query param
    TopicQuery.add_custom_filter(:include_tags) do |results, topic_query|
      if tags_param = topic_query.options[:include_tags]
        tags = tags_param.split(',')
        tag_ids = Tag.where(name: tags).pluck(:id)
        puts "TAGS: #{tag_ids}"

        results = results.where(<<~SQL, tag_ids: tag_ids)
        topics.id IN (
          SELECT topic_tags.topic_id
          FROM topic_tags
          INNER JOIN tags ON tags.id = topic_tags.tag_id
          WHERE tags.id IN (:tag_ids)
        )
        SQL
      end
      results
    end

    # Topic Author
    # Filter by topics where the user is a member of the specified group
    TopicQuery.add_custom_filter(:topic_author) do |results, topic_query|
      if topic_author_param = topic_query.options[:topic_author]
        group = Group.find_by(name: topic_author_param)
        if group
          results = results.where(<<~SQL, group_id: group.id)
          topics.id IN (
            SELECT posts.topic_id
            FROM posts
            INNER JOIN group_users gu ON gu.user_id = posts.user_id
            WHERE gu.group_id = :group_id
            AND posts.post_number = 1
          )
          SQL
        end
      end
      results
    end

    # Has Reply From
    TopicQuery.add_custom_filter(:reply_from) do |results, topic_query|
      if reply_from_param = topic_query.options[:reply_from]
        group = Group.find_by(name: reply_from_param)
        if group
          results = results.where(<<~SQL, group_id: group.id)
          topics.id IN (
            SELECT posts.topic_id
            FROM posts
            INNER JOIN group_users gu ON gu.user_id = posts.user_id
            WHERE gu.group_id = :group_id
            AND posts.post_number > 1
          )
          SQL
        end
      end
      results
    end

    # No Reply From
    TopicQuery.add_custom_filter(:no_reply_from) do |results, topic_query|
      if no_reply_from_param = topic_query.options[:no_reply_from]
        group = Group.find_by(name: no_reply_from_param)
        if group
          results = results.where(<<~SQL, group_id: group.id)
          topics.id NOT IN (
            SELECT posts.topic_id
            FROM posts
            INNER JOIN group_users gu ON gu.user_id = posts.user_id
            WHERE gu.group_id = :group_id
            AND posts.post_number > 1
          )
          SQL
        end
      end
      results
    end

  end
end
