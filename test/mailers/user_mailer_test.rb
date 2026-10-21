require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "price_alert" do
    mail = UserMailer.price_alert
    assert_equal "Price alert", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
