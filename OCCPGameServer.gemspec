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
  spec.summary       = %q{This gem deploys the controlling gameserver required to run a scenario isntance}
  spec.homepage      = "http://www.dfcsc.uri.edu/occp"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  spec.add_runtime_dependency "log4r"
end
