require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:user)).to be_valid
    end

    it "requires email" do
      expect(build(:user, email: nil)).not_to be_valid
    end

    it "requires email to be unique" do
      create(:user, email: "test@example.com")
      expect(build(:user, email: "test@example.com")).not_to be_valid
    end

    it "requires a valid email format" do
      expect(build(:user, email: "not-an-email")).not_to be_valid
    end

    it "requires name" do
      expect(build(:user, name: nil)).not_to be_valid
    end
  end

  describe "has_secure_password" do
    it "sets password_digest on create" do
      user = create(:user)
      expect(user.password_digest).to be_present
    end
  end

  describe "admin" do
    it "defaults to false" do
      user = create(:user)
      expect(user.admin).to be false
    end

    it "can be set to true" do
      user = create(:user, :admin)
      expect(user.admin).to be true
    end
  end

  describe "#first_name" do
    it "returns the first word of name" do
      user = build(:user, name: "Jane Doe")
      expect(user.first_name).to eq("Jane")
    end

    it "returns the full name when it is one word" do
      user = build(:user, name: "Jane")
      expect(user.first_name).to eq("Jane")
    end
  end

  describe "email downcasing" do
    it "downcases email before save" do
      user = create(:user, email: "UPPER@EXAMPLE.COM")
      expect(user.reload.email).to eq("upper@example.com")
    end
  end
end
