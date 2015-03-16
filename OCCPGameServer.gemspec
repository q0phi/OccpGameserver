# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'OCCPGameServer/version'

Gem::Specification.new do |spec|
  spec.name          = "OCCPGameServer"
  spec.version       = OCCPGameServer::VERSION
  spec.authors       = ["DFCSC"]
  spec.email         = ["software@dfcsc.uri.edu"]
  spec.description   = %q{GameServer for the OCCP}
  spec.summary       = %q{This gem deploys the controlling gameserver required to run a scenario instance}
  spec.homepage      = "http://www.dfcsc.uri.edu/occp"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  #spec.executables = ['occpgs']
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "~> 10.1"

  spec.add_runtime_dependency "simple-random", "~> 0.10"
  spec.add_runtime_dependency "eventmachine", "~> 1.0"
  spec.add_runtime_dependency "colorize", "~> 0.7"
  spec.add_runtime_dependency "log4r", "~> 1.1"
  spec.add_runtime_dependency "sqlite3", "~> 1.3"
  spec.add_runtime_dependency "libxml-ruby", "~> 2.7"
  spec.add_runtime_dependency "highline", "~> 1.6"
  spec.add_runtime_dependency "netaddr", "~> 1.5"
  spec.add_runtime_dependency "sinatra", "~> 1.4"
  spec.add_runtime_dependency "thin", "~> 1.6"
  spec.add_runtime_dependency "net-scp", "~> 1.2"
  spec.add_runtime_dependency "mysql2", "~> 0.3.8"
end
