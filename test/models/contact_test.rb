require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "is valid with fixture data" do
    assert contacts(:one).valid?
  end

  test "rejects invalid E.164 phone" do
    contact = contacts(:one).dup
    contact.phone_e164 = "0861112222"

    assert_not contact.valid?
    assert_includes contact.errors[:phone_e164], "is invalid"
  end

  test "rejects invalid priority enum value" do
    contact = contacts(:one).dup
    contact.phone_e164 = "+353861119999"
    contact.priority = 9

    assert_not contact.valid?
    assert_includes contact.errors[:priority], "is not included in the list"
  end

  test "enforces unique phone per user" do
    contact = contacts(:one).dup

    assert_not contact.valid?
    assert_includes contact.errors[:phone_e164], "has already been taken"
  end

  test "allows same phone across different users" do
    contact = contacts(:one).dup
    contact.user = users(:two)

    assert contact.valid?
  end
end
