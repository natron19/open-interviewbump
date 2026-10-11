require "rails_helper"

RSpec.describe Evals::Runner, ".rubric_for" do
  let(:file_rubric) do
    [{ "dimension" => "accurate", "criterion" => "general accuracy" },
     { "dimension" => "useful",   "criterion" => "general usefulness" }]
  end

  it "adds a case's criteria to the file's rubric by default" do
    case_rubric = [{ "dimension" => "accurate", "criterion" => "also mentions X" }]

    expect(described_class.rubric_for(file_rubric, case_rubric).map { |i| i["criterion"] })
      .to eq(["general accuracy", "general usefulness", "also mentions X"])
  end

  it "lets a case criterion marked replaces: true stand in for the file's criterion of that dimension" do
    case_rubric = [{ "dimension" => "accurate", "replaces" => true, "criterion" => "case-specific accuracy" }]

    expect(described_class.rubric_for(file_rubric, case_rubric).map { |i| i["criterion"] })
      .to eq(["general usefulness", "case-specific accuracy"])
  end

  it "uses the file's rubric when the case has none" do
    expect(described_class.rubric_for(file_rubric, nil)).to eq(file_rubric)
  end
end
