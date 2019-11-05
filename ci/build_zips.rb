# rubocop:disable all
puts "Checkout branch #{ARGV[0]}"
system("git checkout #{ARGV[0]} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

puts "Set remote to an http url so that the stage logs look good."
system("git remote set-url origin https://code.ldschurch.org/stash/scm/cf/java-buildpack.git 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

puts "Clean workspace"
system("bundle exec rake clean 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

puts "Building version string for #{ARGV[0]}."
hash = `git rev-parse --short HEAD`.strip

# version = "#{ARGV[1].nil? ? ARGV[0] : ARGV[1]}-#{hash}"
version = "#{ARGV[1].nil? ? ARGV[0] : ARGV[1]}"

puts "Build Bundle zip for #{version}."
system("bundle exec rake package VERSION=#{version} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

puts "Copy java-buildpack-#{version}.zip to release directory."
system("mkdir -p release 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0
system("cp build/java-buildpack-*.zip release/java-buildpack-#{version}-#{hash}.zip.#{ARGV[0]} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0
# rubocop:enable all