require "rails_helper"

RSpec.describe PrepSession, type: :model do
  describe "associations" do
    it "belongs to a user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "has one prep_guide with dependent destroy" do
      assoc = described_class.reflect_on_association(:prep_guide)
      expect(assoc.macro).to eq(:has_one)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe "validations" do
    let(:user) { create(:user) }

    it "is invalid without a user" do
      session = described_class.new(job_title: "Engineer", company: "Stripe", status: "pending")
      expect(session).not_to be_valid
      expect(session.errors[:user]).to be_present
    end

    it "is invalid without a job_title" do
      session = build(:prep_session, user: user, job_title: nil)
      expect(session).not_to be_valid
      expect(session.errors[:job_title]).to be_present
    end

    it "is invalid without a company" do
      session = build(:prep_session, user: user, company: nil)
      expect(session).not_to be_valid
      expect(session.errors[:company]).to be_present
    end

    it "accepts all valid statuses" do
      %w[pending researching complete failed].each do |status|
        session = build(:prep_session, user: user, status: status)
        expect(session).to be_valid, "expected #{status} to be valid"
      end
    end

    it "rejects an invalid status" do
      session = build(:prep_session, user: user, status: "in_progress")
      expect(session).not_to be_valid
      expect(session.errors[:status]).to be_present
    end
  end

  describe "dependent destroy" do
    it "destroys associated prep_guide when the session is destroyed" do
      session = create(:prep_session, :complete)
      create(:prep_guide, prep_session: session)
      expect { session.destroy }.to change(PrepGuide, :count).by(-1)
    end
  end
end
