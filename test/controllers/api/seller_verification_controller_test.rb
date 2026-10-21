require "test_helper"

class Api::SellerVerificationControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get api_seller_verification_create_url
    assert_response :success
  end
end
