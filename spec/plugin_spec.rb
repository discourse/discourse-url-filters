# frozen_string_literal: true

require 'rails_helper'

describe 'plugin' do
  before { SiteSetting.url_filters_enabled = true }

  describe 'Topic Queries' do
    describe 'after_or_before_date' do
      fab!(:topic1) { Fabricate(:topic, created_at: 10.days.ago) }
      fab!(:topic2) { Fabricate(:topic, created_at: 8.days.ago) }
      fab!(:topic3) { Fabricate(:topic, created_at: 6.days.ago) }
      fab!(:user) { Fabricate(:user) }

      it 'only shows topics after specified date' do
        after_date = 9.days.ago.strftime("%Y-%m-%d")
        query = TopicQuery.new(user, { after_date: after_date }).list_latest
        expect(query.topics.length).to eq(2)
        expect(query.topics).to contain_exactly(topic2, topic3)
      end

      it 'only shows topics before specified date' do
        before_date = 9.days.ago.strftime("%Y-%m-%d")
        query = TopicQuery.new(user, { before_date: before_date }).list_latest
        expect(query.topics.length).to eq(1)
        expect(query.topics).to contain_exactly(topic1)
      end

      it 'only shows topics between before and after dates' do
        before_date = 7.days.ago.strftime("%Y-%m-%d")
        after_date = 9.days.ago.strftime("%Y-%m-%d")
        query = TopicQuery.new(user, { before_date: before_date, after_date: after_date }).list_latest
        expect(query.topics.length).to eq(1)
        expect(query.topics).to contain_exactly(topic2)
      end

      it 'does not filter for malformed date' do
        before_date = 'asdf'
        query = TopicQuery.new(user, { before_date: before_date }).list_latest
        expect(query.topics.length).to eq(3)
      end

    end
  end
end
