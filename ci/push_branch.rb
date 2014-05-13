# rubocop:disable all
puts "Checkout branch #{ARGV[0]}"
system("git checkout #{ARGV[0]} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

puts "Push branch #{ARGV[0]}"
system("git push origin #{ARGV[0]} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0
# rubocop:enable all