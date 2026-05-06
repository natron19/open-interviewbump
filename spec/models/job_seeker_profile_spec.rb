require "rails_helper"

RSpec.describe JobSeekerProfile, type: :model do
  describe "associations" do
    it "belongs to a user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "is invalid without a user" do
      profile = described_class.new(background_summary: "Five years experience.")
      expect(profile).not_to be_valid
      expect(profile.errors[:user]).to be_present
    end

    it "is invalid without a background_summary" do
      user    = create(:user)
      profile = described_class.new(user: user)
      expect(profile).not_to be_valid
      expect(profile.errors[:background_summary]).to be_present
    end

    it "accepts a background_summary of exactly 10000 characters" do
      user    = create(:user)
      profile = build(:job_seeker_profile, user: user, background_summary: "a" * 10_000)
      expect(profile).to be_valid
    end

    it "rejects a background_summary over 10000 characters" do
      user    = create(:user)
      profile = build(:job_seeker_profile, user: user, background_summary: "a" * 10_001)
      expect(profile).not_to be_valid
      expect(profile.errors[:background_summary]).to be_present
    end
  end
end
