require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "the manifest and the service worker are served, and the layout links them" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "Sakuya", data["name"]
    assert_equal "standalone", data["display"]
    assert data["icons"].any? { |i| i["purpose"] == "maskable" }
    get pwa_service_worker_path(format: :js)
    assert_response :success
    assert_match "sakuya-#{Sakuya::COMMIT}", response.body
    get login_path
    assert_select "link[rel=manifest]"
    assert_select "meta[name=theme-color][content='#7a90d2']"
    %w[icon-192.png icon-512.png icon-maskable-512.png apple-touch-icon.png offline.html].each { |f| assert File.exist?(Rails.public_path.join(f)), f }
  end
end
