class ClaudeSwitch < Formula
  desc "Keep several Claude Code logins on one machine and launch any of them"
  homepage "https://github.com/ridh21/claude-switch"
  url "https://github.com/ridh21/claude-switch/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "7d5cd033213ea07ad3d2b0de363d04b55645ba9e70001ec8014e9cb0ae06dada"
  license "MIT"
  head "https://github.com/ridh21/claude-switch.git", branch: "main"

  def install
    bin.install "bin/cswitch"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cswitch --version")
  end
end
