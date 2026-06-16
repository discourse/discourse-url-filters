# frozen_string_literal: true

describe Plugin::Instance do
  before { SiteSetting.url_filters_enabled = true }

  describe "Topic Queries" do
    describe "after_or_before_date" do
      fab!(:topic1) { Fabricate(:topic, created_at: 10.days.ago) }
      fab!(:topic2) { Fabricate(:topic, created_at: 8.days.ago) }
      fab!(:topic3) { Fabricate(:topic, created_at: 6.days.ago) }
      fab!(:user)

      it "only shows topics after specified date" do
        after_date = 9.days.ago.strftime("%Y-%m-%d")
        query = TopicQuery.new(user, { after_date: after_date }).list_latest
        expect(query.topics.length).to eq(2)
        expect(query.topics).to contain_exactly(topic2, topic3)
      end

      it "only shows topics before specified date" do
        before_date = 9.days.ago.strftime("%Y-%m-%d")
        query = TopicQuery.new(user, { before_date: before_date }).list_latest
        expect(query.topics.length).to eq(1)
        expect(query.topics).to contain_exactly(topic1)
      end

      it "only shows topics between before and after dates" do
        before_date = 7.days.ago.strftime("%Y-%m-%d")
        after_date = 9.days.ago.strftime("%Y-%m-%d")
        query =
          TopicQuery.new(user, { before_date: before_date, after_date: after_date }).list_latest
        expect(query.topics.length).to eq(1)
        expect(query.topics).to contain_exactly(topic2)
      end

      it "does not filter for malformed date" do
        before_date = "asdf"
        query = TopicQuery.new(user, { before_date: before_date }).list_latest
        expect(query.topics.length).to eq(3)
      end
    end

    describe "hidden tag filters" do
      fab!(:user)
      fab!(:admin)
      fab!(:members_group) { Fabricate(:group, name: "url-filter-members") }
      fab!(:hidden_tag) { Fabricate(:tag, name: "private-tag") }
      fab!(:public_tag) { Fabricate(:tag, name: "public-tag") }
      fab!(:topic_with_hidden_tag) { Fabricate(:topic, tags: [hidden_tag]) }
      fab!(:topic_with_public_tag) { Fabricate(:topic, tags: [public_tag]) }
      fab!(:topic_without_hidden_tag, :topic)

      before do
        Fabricate(
          :tag_group,
          permissions: {
            "staff" => 1,
            members_group.name => 1,
          },
          tag_names: [hidden_tag.name],
        )
      end

      def topic_ids(actor, options)
        TopicQuery.new(actor, options).list_latest.topics.map(&:id)
      end

      it "does not reveal hidden tag associations", :aggregate_failures do
        include_query = TopicQuery.new(user, include_tags: hidden_tag.name).list_latest
        expect(include_query.topics).to be_empty

        # Excluding a tag the user cannot see is a no-op, so the topic carrying
        # the hidden tag must still be present in the list.
        exclude_query = TopicQuery.new(user, exclude_tags: hidden_tag.name).list_latest
        expect(exclude_query.topics).to include(topic_with_hidden_tag, topic_without_hidden_tag)
      end

      it "still filters by a visible tag for a regular user", :aggregate_failures do
        expect(topic_ids(user, include_tags: public_tag.name)).to contain_exactly(
          topic_with_public_tag.id,
        )

        excluded = topic_ids(user, exclude_tags: public_tag.name)
        expect(excluded).to include(topic_with_hidden_tag.id, topic_without_hidden_tag.id)
        expect(excluded).not_to include(topic_with_public_tag.id)
      end

      it "treats a hidden tag the same as a nonexistent one (no oracle)", :aggregate_failures do
        expect(topic_ids(user, include_tags: "does-not-exist")).to be_empty
        expect(topic_ids(user, exclude_tags: "does-not-exist")).to include(topic_with_hidden_tag.id)
      end

      it "does not let a hidden tag in a multi-tag include leak associations" do
        # public-tag is visible, private-tag is not: results must match only the
        # visible tag, never the hidden one.
        expect(
          topic_ids(user, include_tags: "#{public_tag.name},#{hidden_tag.name}"),
        ).to contain_exactly(topic_with_public_tag.id)
      end

      it "lets a member of a permitted group filter by the restricted tag", :aggregate_failures do
        members_group.add(user)

        expect(topic_ids(user, include_tags: hidden_tag.name)).to contain_exactly(
          topic_with_hidden_tag.id,
        )
        expect(topic_ids(user, exclude_tags: hidden_tag.name)).not_to include(
          topic_with_hidden_tag.id,
        )
      end

      it "lets an admin filter by the restricted tag", :aggregate_failures do
        expect(topic_ids(admin, include_tags: hidden_tag.name)).to contain_exactly(
          topic_with_hidden_tag.id,
        )
        expect(topic_ids(admin, exclude_tags: hidden_tag.name)).not_to include(
          topic_with_hidden_tag.id,
        )
      end
    end

    describe "group member filters" do
      fab!(:viewer, :user)
      fab!(:group_member, :user)
      fab!(:other_user, :user)

      fab!(:hidden_members_group) do
        Fabricate(
          :group,
          name: "hidden_members",
          visibility_level: Group.visibility_levels[:public],
          members_visibility_level: Group.visibility_levels[:owners],
        )
      end

      fab!(:member_topic) do
        Fabricate(:topic, user: group_member, title: "Topic by hidden group member")
      end

      fab!(:member_topic_op) do
        Fabricate(:post, topic: member_topic, user: group_member, post_number: 1)
      end

      fab!(:reply_topic) do
        Fabricate(:topic, user: other_user, title: "Topic with hidden group reply")
      end

      fab!(:reply_topic_op) do
        Fabricate(:post, topic: reply_topic, user: other_user, post_number: 1)
      end

      fab!(:member_reply) do
        Fabricate(:post, topic: reply_topic, user: group_member, post_number: 2)
      end

      fab!(:unrelated_topic) { Fabricate(:topic, user: other_user, title: "Unrelated topic") }

      fab!(:unrelated_topic_op) do
        Fabricate(:post, topic: unrelated_topic, user: other_user, post_number: 1)
      end

      before { hidden_members_group.add(group_member) }

      def filtered_topic_ids(options)
        TopicQuery.new(viewer, options).list_latest.topics.map(&:id)
      end

      it "respects hidden group member visibility", :aggregate_failures do
        expect(filtered_topic_ids(topic_author: hidden_members_group.name)).to be_empty
        expect(filtered_topic_ids(reply_from: hidden_members_group.name)).to be_empty
        expect(filtered_topic_ids(no_reply_from: hidden_members_group.name)).to contain_exactly(
          member_topic.id,
          reply_topic.id,
          unrelated_topic.id,
        )
      end
    end
  end
end
