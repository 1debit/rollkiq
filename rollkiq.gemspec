
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rollkiq/version"

Gem::Specification.new do |spec|
  spec.name          = "rollkiq"
  spec.version       = Rollkiq::VERSION
  spec.authors       = ["Fletcher Fowler"]
  spec.email         = ["fletch@fzf.me"]

  spec.summary       = %q{Customize how and when sidekiq sends an exception to rollbar}
  spec.description   = %q{Customize how and when sidekiq sends an exception to rollbar}
  spec.homepage      = "https://github.com/fzf/rollkiq"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'rollbar', '~> 2.18'
  spec.add_dependency 'sidekiq', '~> 5.2'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
end
