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

def unit_test_files
  FileList["test/unit/*_test.coffee"]
end

