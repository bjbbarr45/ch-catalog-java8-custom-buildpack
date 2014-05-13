# rubocop:disable all
require 'fileutils'

home_directory = Dir.pwd

buildpack = ARGV[0]
buildpack_file_suffix = ARGV[1]
position = ARGV[2]
api = ARGV[3]
username = ARGV[4]
password = ARGV[5]

puts "Logging into cf"
system({"HOME" => home_directory}, "cf api #{api} 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

system({"HOME" => home_directory}, "cf auth '#{username}' '#{password}' 2>&1")
exit $?.exitstatus unless $?.exitstatus == 0

Dir["*"].each do |file|
  
  next unless file.end_with?(".zip.#{buildpack_file_suffix}")
  
  filename = file[0..file.rindex('.')-1]

  FileUtils.rm_f(filename)
  FileUtils.cp("#{filename}.#{buildpack_file_suffix}", filename)

  puts "Seeing if #{buildpack} already exists"
  buildpacks = `cf buildpacks`
  exit $?.exitstatus unless $?.exitstatus == 0

  if buildpacks.include?("\n#{buildpack}")
    puts "Unlocking buildpack #{buildpack}"
    system({"HOME" => home_directory}, "cf update-buildpack #{buildpack} --unlock 2>&1")
    
    puts "Update buildpack #{buildpack}"
    system({"HOME" => home_directory}, "cf update-buildpack #{buildpack} -p #{filename} 2>&1")
    exit $?.exitstatus unless $?.exitstatus == 0
  else
    puts "Creating buildpack #{buildpack}"
    system({"HOME" => home_directory}, "cf create-buildpack #{buildpack} #{filename} #{position} 2>&1")
    exit $?.exitstatus unless $?.exitstatus == 0
  end
  
  puts "Update buildpack #{ARGV[0]}"
  system({"HOME" => home_directory}, "cf update-buildpack #{buildpack} --lock 2>&1")
  exit $?.exitstatus unless $?.exitstatus == 0
end
# rubocop:enable all