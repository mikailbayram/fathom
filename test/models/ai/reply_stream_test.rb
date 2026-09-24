require "test_helper"

# The reply the visitor reads is one property of a JSON object the model is
# still writing, so these are about reading a string that is not finished and
# never mistaking the object around it for part of the answer.
class AI::ReplyStreamTest < ActiveSupport::TestCase
  setup { @stream = AI::Responder::ReplyStream.new }

  def feed(*fragments) = fragments.map { |fragment| @stream << fragment }

  test "says nothing until the reply's own value has opened" do
    assert_nil @stream << '{"re'
    assert_nil @stream << "ply"
    assert_nil @stream << '": '
    assert_equal "", @stream.text
  end

  test "hands over the answer as it is written" do
    assert_equal [ nil, "Acme", "Acme supports", "Acme supports RBAC" ],
                 feed('{"reply": "', "Acme", " supports", " RBAC")
  end

  test "stops at the end of the value and ignores the rest of the object" do
    feed('{"reply":"Two per minute.', '"')

    assert_equal "Two per minute.", @stream.text
    assert_nil @stream << ',"used_source_ids":[41,7],"offer_handoff":false}'
    assert_equal "Two per minute.", @stream.text
  end

  test "decodes the escapes a quoted sentence arrives in" do
    feed('{"reply":"They call it \\"Growth\\".\\n\\nOn a 50\\\\50 split.')

    assert_equal %(They call it "Growth".\n\nOn a 50\\50 split.), @stream.text
  end

  test "waits for an escape sequence the wire cut in half" do
    assert_equal "Ask", @stream << '{"reply":"Ask'
    assert_nil @stream << "\\"
    assert_equal "Ask\n", @stream << "n"
  end

  test "waits for a unicode escape rather than showing its digits" do
    assert_equal "caf", @stream << '{"reply":"caf'
    assert_nil @stream << "\\u00"
    assert_equal "café", @stream << "e9"
  end

  # Half a surrogate pair is not a character, and putting one on its own into
  # the reply would make the whole string invalid rather than merely wrong.
  test "waits for the second half of a character built from two escapes" do
    assert_equal "Shipped ", @stream << '{"reply":"Shipped '
    assert_nil @stream << "\\ud83d"
    assert_nil @stream << "\\ude0"
    assert_equal "Shipped 😀", @stream << "0"
  end

  test "a reply abandoned for a search is dropped rather than continued" do
    @stream << '{"reply":"Let me check'
    @stream.reset

    assert_equal "", @stream.text
    assert_equal "Yes, on Enterprise.", @stream << '{"reply":"Yes, on Enterprise.'
  end

  test "reads the reply even when the model writes the object in another order" do
    assert_equal "Yes.", @stream << '{"offer_handoff":false,"reply":"Yes.'
  end
end
