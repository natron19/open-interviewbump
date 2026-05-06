FactoryBot.define do
  factory :job_seeker_profile do
    user
    background_summary { "5 years of backend engineering experience in Python and Go." }
  end
end
