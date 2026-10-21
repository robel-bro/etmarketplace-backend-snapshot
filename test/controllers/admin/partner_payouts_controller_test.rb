require "test_helper"

class Admin::PartnerPayoutsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_partner_payouts_index_url
    assert_response :success
  end

  test "should get show" do
    get admin_partner_payouts_show_url
    assert_response :success
  end

  test "should get create" do
    get admin_partner_payouts_create_url
    assert_response :success
  end

  test "should get update" do
    get admin_partner_payouts_update_url
    assert_response :success
  end
end
