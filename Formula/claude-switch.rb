class ClaudeSwitch < Formula
  desc "Keep several Claude Code logins on one machine and launch any of them"
  homepage "https://github.com/ridh21/claude-switch"
  url "https://github.com/ridh21/claude-switch/archive/refs/tags/v0.4.1.tar.gz"
  sha256 "344dfcc71076055028798b1387cd084c3fe7632c103a50b67a6b9ca3128feb68"
  license "MIT"
  head "https://github.com/ridh21/claude-switch.git", branch: "main"

  def install
    bin.install "bin/cswitch"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cswitch --version")
  end
end
