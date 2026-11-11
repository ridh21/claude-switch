class ClaudeSwitch < Formula
  desc "Keep several Claude Code logins on one machine and launch any of them"
  homepage "https://github.com/ridh21/claude-switch"
  url "https://github.com/ridh21/claude-switch/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "434120eb6ee9b886d324be90ef6edb6e4c654cf451c508a996eb14106128d97e"
  license "MIT"
  head "https://github.com/ridh21/claude-switch.git", branch: "main"

  def install
    bin.install "bin/cswitch"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cswitch --version")
  end
end
