class ClaudeSwitch < Formula
  desc "Keep several Claude Code logins on one machine and launch any of them"
  homepage "https://github.com/ridh21/claude-switch"
  url "https://github.com/ridh21/claude-switch/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "53878593ac462babf1d888014bbde24a541cbfae0be1811cac92818deb57c2c7"
  license "MIT"
  head "https://github.com/ridh21/claude-switch.git", branch: "main"

  def install
    bin.install "bin/cswitch"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cswitch --version")
  end
end
