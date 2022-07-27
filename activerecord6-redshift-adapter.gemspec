Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'activerecord7-redshift-adapter'
  s.version = '1.0.0'
  s.summary = 'Amazon Redshift adapter for ActiveRecord '
  s.description = 'Amazon Redshift adapter for ActiveRecord 7.x.'
  s.license = 'MIT'

  s.author = ['Nancy Foen', 'Minero Aoki', 'iamdbc', 'Quentin Rousseau', 'Johan Le Bray']
  s.email = 'johan@pennylane.com'
  s.homepage = 'https://github.com/pennylane-hq/activerecord7-redshift-adapter'

  s.files = Dir.glob(['LICENSE', 'README.md', 'lib/**/*.rb'])
  s.require_path = 'lib'

  s.required_ruby_version = '>= 2.7'
  s.add_runtime_dependency 'activerecord', '~> 7.0'
  s.add_runtime_dependency 'pg', '~> 1.0'
end
