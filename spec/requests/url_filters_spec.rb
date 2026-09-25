# frozen_string_literal: true

RSpec.describe "URL filters", type: :request do
  fab!(:parent_category, :category)
  fab!(:child_category) { Fabricate(:category, parent_category: parent_category) }
  fab!(:other_category, :category)
  fab!(:parent_topic) { Fabricate(:topic, category: parent_category) }
  fab!(:child_topic) { Fabricate(:topic, category: child_category) }
  fab!(:other_topic) { Fabricate(:topic, category: other_category) }
  fab!(:uncategorized_topic, :topic)

  before { SiteSetting.url_filters_enabled = true }

  it "excludes selected categories and their descendants without excluding uncategorized topics" do
    get "/latest.json", params: { exclude_categories: parent_category.slug }

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.dig("topic_list", "topics").map { |topic| topic["id"] },
    ).to contain_exactly(other_topic.id, uncategorized_topic.id)
  end

  it "does not filter when no selected category exists" do
    get "/latest.json", params: { exclude_categories: "does-not-exist" }

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.dig("topic_list", "topics").map { |topic| topic["id"] },
    ).to contain_exactly(parent_topic.id, child_topic.id, other_topic.id, uncategorized_topic.id)
  end
end
