require "starter/tasks/npm"
require "starter/tasks/npm/release"
require "starter/tasks/git"

desc "Run tests"
task "test" => %w[ test:unit ]

task "test:unit" do
  unit_test_files.each do |path|
    sh "coffee #{path}"
  end
end

task "test:functional" do
  functional_test_files.each do |path|
    sh "coffee #{path}"
  end
end

def unit_test_files
  FileList["test/unit/*_test.coffee"]
end

def functional_test_files
  FileList["test/functional/*_test.coffee"]
end

