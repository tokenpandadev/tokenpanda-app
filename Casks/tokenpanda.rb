# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# The cask for the tap repository tokenpandadev/homebrew-tap, copied there as Casks/tokenpanda.rb.
# RELEASE_VERSION and RELEASE_SHA256 are set by the release: the version of scripts/build-app.sh
# and the SHA-256 it prints for build/tokenpanda-<version>.zip.
cask "tokenpanda" do
  version "RELEASE_VERSION"
  sha256 "RELEASE_SHA256"

  url "https://github.com/tokenpandadev/tokenpanda-app/releases/download/v#{version}/tokenpanda-#{version}.zip"
  name "tokenpanda"
  desc "Menu bar pace for Claude Code plan windows, and the Mac's own figures"
  homepage "https://tokenpanda.dev"

  depends_on macos: ">= :sonoma"

  app "tokenpanda.app"

  uninstall quit: "dev.tokenpanda.app"

  # The app's own Remove runs first, in zap only: uninstall directives also run on every upgrade and would strip
  # the status line entry each time. It is remove.sh, which the app writes into its data folder at Install and
  # Remove, not the app binary: Homebrew before 7.0.10 deletes the app before it runs a zap script. The script
  # lives until the trash step below. It is the same Remove as `tokenpanda --remove-status-line`, in sh and plutil.
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
    open System Settings, Privacy & Security, and click Open Anyway.

    brew uninstall --zap removes the status line entry and puts back the one
    you had before, for an entry installed with tokenpanda 0.1.9 or later.
    With a plain brew uninstall, or an entry from an older version, first open
    tokenpanda's Settings tab and click "Remove the status line entry".
  EOS
end
