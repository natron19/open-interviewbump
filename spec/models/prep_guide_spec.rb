require "rails_helper"

RSpec.describe PrepGuide, type: :model do
  describe "associations" do
    it "belongs to a prep_session" do
      assoc = described_class.reflect_on_association(:prep_session)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "is invalid without a prep_session" do
      guide = described_class.new
      expect(guide).not_to be_valid
      expect(guide.errors[:prep_session]).to be_present
    end
  end

  describe "JSON fields" do
    let(:guide) { create(:prep_guide) }

    it "stores sources as valid JSON that round-trips through JSON.parse" do
      expect { JSON.parse(guide.sources) }.not_to raise_error
      expect(JSON.parse(guide.sources)).to be_an(Array)
    end

    it "stores agent_trace as valid JSON that round-trips through JSON.parse" do
      expect { JSON.parse(guide.agent_trace) }.not_to raise_error
      expect(JSON.parse(guide.agent_trace)).to be_an(Array)
    end
  end
end
