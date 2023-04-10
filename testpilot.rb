class Testpilot < Formula
  desc "Automated end-to-end tests for mobile apps using GPT."
  homepage "https://github.com/workco/TestPilot"
  url "https://fjcaetano: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@github.com/workco/TestPilot.git", :using => :git, :branch => "main" # TODO: use HTTPS when going public
  version "0.1.0"

  depends_on xcode: ["13.0", :build]

  def install
    system "swift", "build", "--product", "testpilot", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/testpilot"
  end

  test do
    system "which", "testpilot"
  end
end
