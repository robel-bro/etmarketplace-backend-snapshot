require "test_helper"

class Api::BuyerVerificationControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get api_buyer_verification_create_url
    assert_response :success
  end
end
