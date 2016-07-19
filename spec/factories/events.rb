FactoryGirl.define do
  factory :event do
    user_id 1
    event_type :account_created
    user_agent 'Chrome 99'
    ip_address '192.168.0.1'
  end
end
