require "rails_helper"

RSpec.describe Evals::Checks do
  def ctx(output, variables: {}, trace: [], duration_ms: 100)
    Evals::Checks::Context.new(output: output, variables: variables, trace: trace, duration_ms: duration_ms)
  end

  def run(check, context)
    Evals::Checks.run(check.stringify_keys, context).first
  end

  let(:agenda) do
    { "title" => "Workshop", "activities" => [
      { "name" => "Intro", "minutes" => 10, "score" => 9 },
      { "name" => "Build", "minutes" => "35 min", "score" => 7 },
      { "name" => "Share", "minutes" => 15, "score" => 4 },
    ] }.to_json
  end

  it "checks JSON structure" do
    expect(run({ type: "json_valid" }, ctx(agenda))).to be true
    expect(run({ type: "has_keys", keys: %w[title activities] }, ctx(agenda))).to be true
    expect(run({ type: "has_keys", keys: %w[owner] }, ctx(agenda))).to be false
    expect(run({ type: "each_has_keys", path: "activities", keys: %w[name minutes] }, ctx(agenda))).to be true
  end

  it "checks counts, sums, ordering and allowed values" do
    expect(run({ type: "count_between", path: "activities", min: 3, max: 5 }, ctx(agenda))).to be true
    expect(run({ type: "count_between", path: "activities", min: 4, max: 5 }, ctx(agenda))).to be false
    expect(run({ type: "sum_equals", path: "activities", field: "minutes", value: "{{duration}}" },
               ctx(agenda, variables: { "duration" => "60 minutes" }))).to be true
    expect(run({ type: "sorted_desc", path: "activities", field: "score" }, ctx(agenda))).to be true
    expect(run({ type: "values_in", path: "activities", field: "name", allowed: %w[intro build] }, ctx(agenda))).to be false
  end

  it "checks text length and content" do
    expect(run({ type: "max_words", value: 3 }, ctx("one two three four"))).to be false
    expect(run({ type: "max_chars", value: 280 }, ctx("short tweet"))).to be true
    expect(run({ type: "contains_all", values: ["{{company}}"] }, ctx("Hello Acme team", variables: { "company" => "acme" }))).to be true
    expect(run({ type: "not_contains", values: ["Stanford"] }, ctx("Studied at Stanford"))).to be false
    expect(run({ type: "matches", pattern: "^\\d+\\." }, ctx("1. First"))).to be true
  end

  it "checks agent traces and latency" do
    trace = [{ tool: "search_web", args: {} }, { tool: "fetch_url", args: {} }]
    expect(run({ type: "tools_subset_of", values: %w[search_web fetch_url] }, ctx("x", trace: trace))).to be true
    expect(run({ type: "tools_subset_of", values: %w[search_web] }, ctx("x", trace: trace))).to be false
    expect(run({ type: "max_tool_calls", value: 1 }, ctx("x", trace: trace))).to be false
    expect(run({ type: "called_tool", value: "fetch_url" }, ctx("x", trace: trace))).to be true
    expect(run({ type: "latency_under_ms", value: 50 }, ctx("x", duration_ms: 100))).to be false
  end

  it "fails, rather than raising, on an unknown or misconfigured check" do
    expect(Evals::Checks.run({ "type" => "nope" }, ctx("x"))).to match([false, /Unknown/])
    expect(Evals::Checks.run({ "type" => "max_words" }, ctx("x"))).to match([false, /errored/])
  end
end
