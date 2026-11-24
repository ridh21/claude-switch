class ClaudeSwitch < Formula
  desc "Keep several Claude Code logins on one machine and launch any of them"
  homepage "https://github.com/ridh21/claude-switch"
  url "https://github.com/ridh21/claude-switch/archive/refs/tags/v0.4.3.tar.gz"
  sha256 "896768f0457a230d459b290395366b33bd625dc93672e8c1db5b1f2897984e4f"
  license "MIT"
  head "https://github.com/ridh21/claude-switch.git", branch: "main"

  def install
    bin.install "bin/cswitch"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cswitch --version")
  end
end
