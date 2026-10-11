cask "macspanso" do
  version "1.5.0"
  sha256 "PLACEHOLDER_UPDATED_BY_RELEASE_WORKFLOW"

  url "https://github.com/jeffcaldwellca/macspanso/releases/download/v#{version}/macspanso-#{version}.dmg"
  name "macspanso"
  desc "macOS GUI for the espanso text expander"
  homepage "https://github.com/jeffcaldwellca/macspanso"

  depends_on cask: "espanso"

  app "macspanso.app"

  zap trash: [
    "~/Library/Application Support/macspanso",
    "~/Library/Preferences/com.macspanso.macspanso.plist",
  ]
end
