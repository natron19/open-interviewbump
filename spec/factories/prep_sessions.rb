FactoryBot.define do
  factory :prep_session do
    user
    job_title { "Software Engineer" }
    company   { "Acme Corp" }
    status    { "pending" }

    trait :complete do
      status { "complete" }
    end

    trait :failed do
      status        { "failed" }
      error_message { "Gemini error" }
    end

    trait :researching do
      status { "researching" }
    end
  end
end
