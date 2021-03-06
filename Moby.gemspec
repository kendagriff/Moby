# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'Moby/version'

Gem::Specification.new do |gem|
  gem.name          = "Moby"
  gem.version       = Moby::VERSION
  gem.authors       = ["Rune Funch Søltoft"]
  gem.email         = ["funchsoltoft@gmail.com  "]
  gem.description   = %q{"Moby"}
  gem.summary       = %q{Moby}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_runtime_dependency 'sexp_processor', "~>3.2", "=3.2.0"
  gem.add_runtime_dependency 'ruby_parser',"~>2.0", "=2.0.6"
  gem.add_runtime_dependency 'ruby2ruby',"~>1.3",">=1.3.1"
  gem.add_runtime_dependency 'live_ast',"~>1.0",">=1.0.2"
end
