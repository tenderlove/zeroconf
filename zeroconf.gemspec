require_relative "lib/zeroconf/version"

Gem::Specification.new do |s|
  s.name        = "zeroconf"
  s.version     = ZeroConf::VERSION
  s.summary     = "Multicast DNS client and server"
  s.description = "This is a multicast DNS client and server written in Ruby"
  s.authors     = [ "Aaron Patterson" ]
  s.email       = "tenderlove@ruby-lang.org"
  s.files       = `git ls-files -z`.split("\x0")
  s.test_files  = s.files.grep(%r{^test/})
  s.homepage    = "https://github.com/tenderlove/zeroconf"
  s.license     = "Apache-2.0"

  s.add_dependency("resolv", "~> 0.3.0")
  s.add_development_dependency("rake", "~> 13.0")
  s.add_development_dependency("minitest", "~> 5.20")
end
