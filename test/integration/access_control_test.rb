require "test_helper"

class AccessControlTest < ActionDispatch::IntegrationTest
  setup { @lead = Lead.for_website("https://acme.test") }

  # Integration requests come from 127.0.0.1, which is the one case the wall
  # stands aside for. Everything here asks for the password explicitly.
  def with_credentials(username: "operator", password: "letmein")
    with_env("FATHOM_USERNAME" => username, "FATHOM_PASSWORD" => password) { yield }
  end

  def header_for(username, password)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  test "the internal application asks for a password" do
    with_credentials do
      get root_path

      assert_response :unauthorized
    end
  end

  test "the right password gets in" do
    with_credentials do
      get root_path, headers: header_for("operator", "letmein")

      assert_response :success
    end
  end

  test "a wrong password does not" do
    with_credentials do
      get lead_path(@lead), headers: header_for("operator", "guessing")

      assert_response :unauthorized
    end
  end

  test "a wrong username does not either" do
    with_credentials do
      get root_path, headers: header_for("nobody", "letmein")

      assert_response :unauthorized
    end
  end

  test "every internal surface is behind it, not only the pages" do
    scan = Scan.start!(@lead)

    with_credentials do
      get status_lead_path(@lead)
      assert_response :unauthorized

      get finding_path(finding_for(scan))
      assert_response :unauthorized

      post rescan_lead_path(@lead)
      assert_response :unauthorized
    end
  end

  test "an unconfigured deployment is closed, not open" do
    with_env("FATHOM_USERNAME" => nil, "FATHOM_PASSWORD" => nil) do
      assert_not Fathom::BasicAuth.configured?
      assert_not Fathom::BasicAuth.valid?("", "")
    end
  end

  test "the shared demo stays shareable" do
    chatbot = chatbot_for(Scan.start!(@lead))

    with_credentials do
      get public_demo_path(chatbot.slug)

      assert_response :success
    end
  end

  test "passing the password marks the operator for the socket" do
    with_credentials do
      get root_path, headers: header_for("operator", "letmein")

      assert cookies[Fathom::BasicAuth::OPERATOR_COOKIE.to_s].present?,
             "the socket cannot ask for a password, so it reads this"
    end
  end

  test "nothing here is indexable" do
    get root_path

    assert_equal "noindex, nofollow, noarchive, nosnippet", response.headers["X-Robots-Tag"]
    assert_includes Rails.public_path.join("robots.txt").read, "Disallow: /"
  end

  test "a shared demo is not indexable either" do
    chatbot = chatbot_for(Scan.start!(@lead))
    get public_demo_path(chatbot.slug)

    assert_equal "noindex, nofollow, noarchive, nosnippet", response.headers["X-Robots-Tag"]
  end

  private
    def finding_for(scan)
      claim = scan.claims.create!(question_text: "Anything?", statement: "Something.",
                                  category: "security_compliance", buyer_importance: 0.5, support: 0.9)
      claim.create_finding!(scan: scan, answer: "Something.", status: "viable")
    end

    def chatbot_for(scan)
      scan.create_chatbot!(name: "Acme", slug: "acme-#{SecureRandom.hex(3)}", public: true, status: "active")
    end
end
