# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# The cask for the tap repository tokenpandadev/homebrew-tap, copied there as Casks/tokenpanda.rb.
# RELEASE_VERSION and RELEASE_SHA256 are set by the release: the version of the tag, and the SHA-256 in the
# tokenpanda-<version>.zip.sha256 that .github/workflows/release.yml attaches to the draft (the zip CI built).
cask "tokenpanda" do
  version "RELEASE_VERSION"
  sha256 "RELEASE_SHA256"

  url "https://github.com/tokenpandadev/tokenpanda-app/releases/download/v#{version}/tokenpanda-#{version}.zip"
  name "tokenpanda"
  desc "Menu bar pace for Claude Code plan windows, and the Mac's own figures"
  homepage "https://tokenpanda.dev"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "tokenpanda.app"

  uninstall quit: "dev.tokenpanda.app"

  # The app's own Remove runs first, in zap only: uninstall directives also run on every upgrade and would strip
  # the status line entry each time. It is remove.sh, which the app writes into its data folder at Install and
  # Remove, not the app binary: Homebrew before 7.0.10 deletes the app before it runs a zap script. The script
  # lives until the trash step below. It is the same Remove as `tokenpanda --remove-status-line`, in sh, with osascript for the JSON edit and plutil as the fallback.
  zap script: {
        executable:   "/bin/sh",
        args:         ["-c", '[ ! -f "$0" ] || /bin/sh "$0"',
                       File.expand_path("~/Library/Application Support/dev.tokenpanda.app/remove.sh")],
        must_succeed: false,
      },
      trash:  [
        "~/Library/Application Support/dev.tokenpanda.app",
        "~/Library/Preferences/dev.tokenpanda.app.plist",
      ]

  caveats <<~EOS
    The app is signed ad hoc, not notarised. On first launch macOS blocks it:
    open System Settings, Privacy & Security, and click Open Anyway. The warning
    comes back once more: click Open Anyway again and enter your Mac password
    or use Touch ID.

    brew uninstall --zap removes the status line entry and puts back the one
    you had before, once tokenpanda 0.1.9 or later has run at least once.
    With a plain brew uninstall, first open tokenpanda's Settings tab and
    click "Remove the status line entry".
  EOS
end
