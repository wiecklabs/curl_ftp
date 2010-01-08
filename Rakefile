require "rubygems"
require "pathname"
require "rake"
require "rake/testtask"

# Gem
require "rake/gempackagetask"

NAME = "curl_ftp"
SUMMARY = "Interact with FTP servers via curl"
GEM_VERSION = "0.1.1"

spec = Gem::Specification.new do |s|
  s.name = NAME
  s.summary = s.description = SUMMARY
  s.author = "Wieck Media"
  s.email = "dev@wieck.com"
  s.version = GEM_VERSION
  s.platform = Gem::Platform::RUBY
  s.require_path = 'lib'
  s.files = %w(Rakefile) + Dir.glob("{lib}/**/*")
  s.homepage = "http://wiecklabs.com"
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

desc "Install CurlFtp as a gem"
task :install => [:repackage] do
  sh %{gem install pkg/#{NAME}-#{GEM_VERSION}}
end