class Qavinci < Formula
  desc "Automated end-to-end tests for mobile apps using GPT."
  homepage "https://github.com/workco/qavinci-poc"
  url "git@github.com:workco/qavinci-poc.git", :using => :git, :branch => "main" # TODO: use HTTPS when going public
  version "0.1.0"

  depends_on xcode: ["13.0", :build]

  def install
    system "swift", "build", "--product", "qavinci", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/qavinci"
  end

  test do
    system "which", "qavinci"
  end
end
